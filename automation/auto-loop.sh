#!/usr/bin/env bash
# auto-loop.sh — Cairn 自动化守护
#
# 监听 inbox/,新文件一落地就触发 headless Claude,按 vault 里的 AGENTS.md
# 执行 ingest(消化该源)+ loop(MEASURE→LINT→PLAN)。你只管"丢文件",其余全自动。
#
# 有 fswatch 就即时;没有则自动退化为 5s 轮询 —— 零依赖也能跑。
#
# 用法:
#   CAIRN_VAULT=/path/to/vault ./auto-loop.sh            # 前台运行(看日志、调试)
#   CAIRN_VAULT=/path/to/vault ./auto-loop.sh --once      # 只处理当前 inbox 里 pending 的,然后退出
#   CAIRN_VAULT=/path/to/vault ./auto-loop.sh --install   # 装 launchd,开机自启 + 崩溃自重启
#   DRY_RUN=1 CAIRN_VAULT=... ./auto-loop.sh              # 只走管线不调 claude(验证用)
#
# 环境变量:
#   CAIRN_VAULT       必填。vault 根目录(须含 AGENTS.md)
#   CAIRN_INBOX       可选。投件箱,默认 $CAIRN_VAULT/inbox
#   CAIRN_RUNTIME     可选。运行时目录(日志/归档/锁),默认 $CAIRN_VAULT/.cairn
#                     —— Tolaria/Obsidian 这类会递归扫描的 vault,建议设到 vault 外,避免被当笔记索引。
#   CAIRN_PROCESSED   可选。已处理存档,默认 $CAIRN_RUNTIME/processed
#   POLL_SECONDS      可选。无 fswatch 时的轮询间隔,默认 5
#   SETTLE_SECONDS    可选。fswatch 事件沉淀(去抖)窗口,默认 2

set -euo pipefail

# ────────────────────────── 配置 ──────────────────────────
: "${CAIRN_VAULT:?❌ 必须设置 CAIRN_VAULT(指向含 AGENTS.md 的 vault 根目录)}"
CAIRN_INBOX="${CAIRN_INBOX:-$CAIRN_VAULT/inbox}"
RUNTIME_DIR="${CAIRN_RUNTIME:-$CAIRN_VAULT/.cairn}"
CAIRN_PROCESSED="${CAIRN_PROCESSED:-$RUNTIME_DIR/processed}"
POLL_SECONDS="${POLL_SECONDS:-5}"
SETTLE_SECONDS="${SETTLE_SECONDS:-2}"
LOG_FILE="$RUNTIME_DIR/auto-loop.log"
LOCK_DIR="$RUNTIME_DIR/.lock"

# headless claude 允许的工具(收口权限:只读写文件 + 检索,不给任意 shell)。
# 用 Tolaria MCP 的话,追加如 --allowedTools mcp__tolaria__create_note 等;要完全不限制则改用 --dangerously-skip-permissions。
ALLOWED_TOOLS=(--allowedTools Read --allowedTools Write --allowedTools Edit --allowedTools Glob --allowedTools Grep)

mkdir -p "$RUNTIME_DIR" "$CAIRN_PROCESSED"

# ────────────────────────── 工具 ──────────────────────────
log() { printf '[%s] %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$*" | tee -a "$LOG_FILE" >&2; }

preflight() {
  command -v claude >/dev/null || { log "❌ 未找到 claude CLI(需装 Claude Code)"; exit 1; }
  [ -f "$CAIRN_VAULT/AGENTS.md" ] || { log "❌ $CAIRN_VAULT/AGENTS.md 不存在 —— 不是 Cairn vault?"; exit 1; }
  mkdir -p "$CAIRN_INBOX"
}

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "$$" >"$LOCK_DIR/pid"
    return 0
  fi
  # 陈旧锁:持有者进程已不在,清掉重试
  local pid; pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
    log "⚠️ 清理陈旧锁(原 pid $pid 已退出)"
    rm -rf "$LOCK_DIR" && mkdir "$LOCK_DIR" && echo "$$" >"$LOCK_DIR/pid" && return 0
  fi
  return 1
}
release_lock() { rm -rf "$LOCK_DIR" 2>/dev/null || true; }

# ────────────────────────── 核心 ──────────────────────────
ingest_one() {
  local file="$1"
  case "$(basename "$file")" in .*) return 0;; esac   # 跳过隐藏文件
  [ -f "$file" ] || return 0                           # 跳过目录

  log "▶ ingest + loop: $file"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log "  (DRY_RUN: 跳过 claude 调用)"
  else
    local prompt
    prompt=$(cat <<EOF
你正在 Cairn vault "$CAIRN_VAULT" 里执行自动化回路。一个新的源文件出现在:
  $file

先完整读取 $CAIRN_VAULT/AGENTS.md(以及它通过 @ 引入的任何文件),严格按其中的协议执行。
注意:你不会自动加载 @-import,需要自己 Read 那些被引入的 schema 文件。

1. ingest("$file") —— 读取该源文件。若它还不是合规 Source(type:Source),先用其内容建一个 Source 笔记(status:Unprocessed)再消化:
   建/更新 Summary(TL;DR + Key points + Quotes)、更新触及的 Entity/Concept(双向回填 mentions / mentioned_in)、
   把该 Source 标为 status:Digested 并设 derived_into、更新 index、向 log 追加一行。
2. loop() —— 刷新 wiki-health(MEASURE,含概念饥饿度等 KPI)、跑 lint、PLAN 决定下一个源并写入 wiki-health §本轮决策。
默认按纯 markdown 读写(除非你有更丰富的笔记工具)。最后用 2–3 句话汇报做了什么。
EOF
)
    if ( cd "$CAIRN_VAULT" && claude -p --add-dir "$CAIRN_VAULT" "${ALLOWED_TOOLS[@]}" "$prompt" >>"$LOG_FILE" 2>&1 ); then
      log "✅ 完成: $file"
    else
      log "❌ claude 失败: $file(详见 $LOG_FILE)"
      return 1
    fi
  fi
  # 处理完归档原文件,避免重复触发(文件名加时间戳防冲突)
  mv "$file" "$CAIRN_PROCESSED/$(date +%s)-$(basename "$file")" 2>/dev/null || true
}

process_pending() {
  shopt -s nullglob
  local files=( "$CAIRN_INBOX"/* )
  [ "${#files[@]}" -eq 0 ] && return 0
  acquire_lock || { log "⏸ 另一实例正在跑,跳过本轮"; return 0; }
  local f
  for f in "${files[@]}"; do
    ingest_one "$f" || true
  done
  release_lock
}

# ────────────────────────── 监听 ──────────────────────────
watch_poll() {
  log "🔄 poll 模式(每 ${POLL_SECONDS}s 扫一次)。装 fswatch 可切即时:brew install fswatch"
  while true; do
    process_pending || true
    sleep "$POLL_SECONDS"
  done
}

watch_fswatch() {
  log "⚡ fswatch 即时模式。监听: $CAIRN_INBOX"
  fswatch -0 --latency "$SETTLE_SECONDS" \
    --event Created --event Updated --event Renamed \
    "$CAIRN_INBOX" | while IFS= read -r -d '' _event; do
      # 去抖:吞掉沉淀窗口内的连发事件,再统一处理
      while IFS= read -r -d '' -t "$SETTLE_SECONDS" _; do :; done
      process_pending || true
    done
}

# ────────────────────────── launchd 自启 ──────────────────────────
do_install() {
  preflight
  local script label plist launch_path
  script="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  label="com.cairn.auto-loop"
  plist="$HOME/Library/LaunchAgents/${label}.plist"
  # launchd 不继承登录 shell 的 PATH —— 显式给出,确保 claude / fswatch 可被守护进程发现
  launch_path="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin"
  cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string><string>${script}</string>
  </array>
  <key>WorkingDirectory</key><string>${CAIRN_VAULT}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CAIRN_VAULT</key><string>${CAIRN_VAULT}</string>
    <key>CAIRN_RUNTIME</key><string>${RUNTIME_DIR}</string>
    <key>PATH</key><string>${launch_path}</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${RUNTIME_DIR}/launchd.out.log</string>
  <key>StandardErrorPath</key><string>${RUNTIME_DIR}/launchd.err.log</string>
</dict>
</plist>
EOF
  launchctl unload "$plist" 2>/dev/null || true
  launchctl load -w "$plist" 2>/dev/null || launchctl bootstrap "gui/$(id -u)" "$plist"
  log "✅ launchd 已装: $plist"
  log "   vault=$CAIRN_VAULT  runtime=$RUNTIME_DIR"
  log "   开机自启 + 崩溃自重启。日志: $RUNTIME_DIR/launchd.{out,err}.log"
  log "   卸载: launchctl unload \"$plist\""
}

# ────────────────────────── 入口 ──────────────────────────
main() {
  preflight
  case "${1:-}" in
    --install) do_install; exit 0;;
    --once)    log "=== 一次性处理 ==="; process_pending; exit 0;;
  esac
  log "=== Cairn auto-loop 启动 ==="
  log "vault=$CAIRN_VAULT inbox=$CAIRN_INBOX runtime=$RUNTIME_DIR DRY_RUN=${DRY_RUN:-0}"
  if command -v fswatch >/dev/null 2>&1; then
    watch_fswatch
  else
    watch_poll
  fi
}

main "$@"
