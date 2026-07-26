# 自动化:`auto-loop.sh`

> 你只管把材料丢进 `inbox/`,消化 + 转 loop 全自动。

`auto-loop.sh` 是一个本地守护:监听 `inbox/`,一旦有新文件落地,就触发 headless Claude,按 vault 里的 `AGENTS.md` 把它 `ingest` 成 Summary/Entity/Concept,再转一整圈 loop(MEASURE→LINT→PLAN)。原始文件随后归档,不再重复触发。

```
   你丢文件 ──▶ inbox/ ──▶ [auto-loop 监听] ──▶ headless Claude
                                                  │
                            ┌─────────────────────┤
                            ▼                     ▼
                     ingest(该源)            loop()
                   建 Summary/Concept      刷新 wiki-health
                                                  │
                                          原文件 ▶ .cairn/processed/
```

## 要求

- **Claude Code CLI**(`claude` 在 PATH 里,已登录)。
- **fswatch**(可选,即时触发):`brew install fswatch`。没装也能用,自动退化为 5 秒轮询。

## 三步上手

```bash
# 1. 指向你的 vault(须含 AGENTS.md)
export CAIRN_VAULT=/path/to/your/vault

# 2. 跑起来(前台,先验证)
./automation/auto-loop.sh

# 3. 丢个源进去,看它自动消化
echo "# 一篇值得读的文章 ..." > "$CAIRN_VAULT/inbox/my-first-source.md"
```

想让它**常驻、开机自启、崩溃自重启**:

```bash
./automation/auto-loop.sh --install    # 装 launchd(仅 macOS)
```

## 运行模式

| 命令 | 行为 |
|---|---|
| `./auto-loop.sh` | 前台守护。fswatch 即时 / poll 回退。`Ctrl-C` 退出。 |
| `./auto-loop.sh --once` | 只处理当前 `inbox/` 里的 pending 文件,然后退出。适合 cron 或一次性清仓。 |
| `./auto-loop.sh --reconcile` | 不 ingest,只跑 lint + MEASURE:清理悬空引用 / 孤儿、刷新 `wiki-health`。**删完笔记后跑一下**。 |
| `./auto-loop.sh --install` | 写入 launchd plist 并加载,开机自启(KeepAlive 崩溃自重启)。 |
| `DRY_RUN=1 ./auto-loop.sh` | 只走管线(检测→归档),不调用 claude。验证监听与锁用。 |

## 删除怎么办

守护**只管 ingest,不监听删除**——这是有意的:监听整个 vault 的删除会 thrash(每次编辑都是删+建),可能误伤正在编辑的笔记。

Cairn 用 **lint 对账**处理删除,而不是事件反应。你删一个节点 → 留下悬空引用 → 下次 `lint` 检测到并修(剪掉死的 `mentions`/`mentioned_in`、Source 退回 `Unprocessed`、孤儿 Concept 合并/删)。

- **每次 ingest 的 loop 里已经自动跑 lint** —— 所以只要你还在往 `inbox/` 喂源,删除残留会被顺手清掉,无需额外操作。
- **只删不增**时,手动跑一次对账:`./auto-loop.sh --reconcile`。它只做 lint + 刷新 `wiki-health`,不碰 `inbox/`。
- **完全不想管**:装每日定时对账 `./auto-loop.sh --install-reconcile`。三重保证"每天一次":① 凌晨定时(默认 04:17,`RECONCILE_HOUR`/`RECONCILE_MINUTE` 改时刻);② **开机/登录时补跑**(`RunAtLoad`——解决"那个点电脑没开机",休眠错过也在唤醒时补);③ **一次/日去重门**(同一天多次开机不重复跑;手动 `--reconcile` 不受限)。与 inbox 守护共用一把锁、互不冲突。成本无感的可选项。

## 配置(环境变量)

| 变量 | 默认 | 说明 |
|---|---|---|
| `CAIRN_VAULT` | **必填** | vault 根目录(含 `AGENTS.md`) |
| `CAIRN_INBOX` | `$CAIRN_VAULT/inbox` | 投件箱,新源丢这里 |
| `CAIRN_PROCESSED` | `$CAIRN_VAULT/.cairn/processed` | 处理完的原始文件归档处 |
| `POLL_SECONDS` | `5` | 无 fswatch 时的轮询间隔 |
| `SETTLE_SECONDS` | `2` | fswatch 事件去抖窗口 |

## 权限说明(重要)

headless 模式下 Claude 没法弹窗征求许可,所以脚本默认**收口工具权限**:

```
--allowedTools Read Write Edit Glob Grep
```

只允许读写文件 + 检索 —— 够 Cairn 按 markdown 跑完整套 ingest+loop,但不给任意 shell。

- **用 Tolaria MCP**:在脚本的 `ALLOWED_TOOLS` 数组里追加,如 `--allowedTools mcp__tolaria__create_note` 等。
- **完全不限制**:把 `ALLOWED_TOOLS` 那行换成 `--dangerously-skip-permissions`(仅当你完全信任该 vault、且需要最大灵活度时)。

## macOS:Desktop 与 TCC(用 `--install` 必读)

launchd 守护**不继承你登录 shell 的两样东西**,都得显式处理:

1. **PATH** —— 脚本已在 plist 里写死(`/opt/homebrew/bin`、`/usr/local/bin`、`~/.local/bin` 等),`claude` / `fswatch` 能被找到。无需手动。
2. **磁盘访问(TCC)** —— 会卡住人的地方。若 vault 在受保护目录(`~/Desktop`、`~/Documents`、`~/Downloads`),launchd 守护**没有访问权限**,日志报 `Operation not permitted` / `getcwd: cannot access parent directories`,并崩坏重启。

   解决:系统设置 → 隐私与安全性 → **完全磁盘访问权限**,把 `/bin/bash` 拖进去通常就够 —— bash 的 FDA 会覆盖它 fork/exec 出的 `claude` 子进程(macOS TCC 按执行链继承,实测有效)。

   Finder 里 `前往 → 前往文件夹` 输 `/bin` 找到 `bash`,**直接拖进 FDA 列表**(用 `+` 文件框常加不进系统二进制,拖拽可靠)。改完重载:`./auto-loop.sh --install`。

   极少数情况下若 `claude` 仍单独报权限错,再把 `claude` 本体(`which claude` 看路径)也拖进去 —— 但先别急着加,bash 的 FDA 多半已覆盖。

   不想给 FDA?把 vault 放在非保护区(如 `~/kb`),或改用前台 / tmux 跑(继承终端权限)。

## 日志与排错

- 操作日志:`$CAIRN_VAULT/.cairn/auto-loop.log`(claude 的输出也写在这里)。
- launchd 日志:`$CAIRN_VAULT/.cairn/launchd.{out,err}.log`。
- **没反应?** 先 `DRY_RUN=1` 跑,确认文件能被检测到并归档;再正式跑看 `.cairn/auto-loop.log` 里 claude 的报错。
- **并发保护**:同一时刻只跑一个 ingest(`.cairn/.lock/`);持有者进程意外退出会留陈旧锁,脚本检测到会自动清理。

## 它不做什么(诚实声明)

- **不替你抓源。** 它消化你丢进来的东西,不主动从网络获取材料 —— 那会引入质量风险,与 Cairn "deliberate source" 的哲学冲突。你可以自己用 RSS/爬虫往 `inbox/` 喂,但它不做这一步。
- **健康页仍是快照**,不是实时。每个 loop 转完刷新一次,与手跑一致。
