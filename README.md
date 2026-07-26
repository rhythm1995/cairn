# Cairn

> Turn what you read into knowledge that compounds.

山道岔口,旅人垒石,为后来者指路。每一块石头都在说:"我走过这里,我知道。"

**Cairn** 把这件事交给 LLM:每读进一篇原始材料,就往你的知识图谱里添一块石头——提炼成结构化页面、链接进既有概念、标出它与旧结论的张力,让主张随新证据自我修正。读过的不必再读,记下的会持续增值。

它不是一个 app,也没有数据库。它是一套**文件协议**:四种页面、一张关系图、一个闭环。源自 [Karpathy 的 LLM Wiki 思想](https://karpathy.bearblog.dev/the-llm-wiki/),工程化为任何能读写 Markdown、懂 wikilink 与 frontmatter 的 agent 都能照做的约定。

---

## 为什么需要它

LLM 把一件事的成本压到了接近零:**把一篇材料读完,提炼成结构化页面,链接进既有图谱**。

这意味着知识第一次可以被当成**资产**来经营——读过的源不必每次重读,提炼过的结论可以复用、可以被推翻、可以随时间增值。前提是,得有一套让 agent 知道"怎么消化、怎么链接、怎么不腐烂"的协议。

大多数人的"知识管理"是反的:要么是**一堆孤立的笔记**(永远不会被综合),要么是**每次提问都让 LLM 重读原始材料**(永不复用、永不积累)。Cairn 是第三条路——**一次消化,永久复用,持续校准**。

## 核心思想

1. **Compounding artifact** —— 知识库建一次,持续更新。不要在每个问题上重新从源派生。先读已有的页。
2. **Sources are immutable** —— 原始材料永不修改。重新消化产出*新的* Summary,旧的标 `Superseded`,历史可追溯。
3. **Types + relationships over folders** —— 意义来自 `type:` 和 `[[wikilinks]]`,不是目录。这让知识可被机器遍历、可被 agent 理解、可跨工具迁移。
4. **Your own words** —— Summary 是转述,Entity/Concept 是综合。逐字引用只在 `## Quotes` 下,并标来源。
5. **Cite everything** —— 每个 claim 都链接它来自的 Summary(从而链回 Source)。
6. **Loop, not one-shot** —— 维护是飞轮,不是一次性操作。每次消化都闭环:消化 → 度量 → 清理 → 规划下一篇。

## 架构

| 层 | 内容 |
|---|---|
| **Raw**(不可变源) | `Source` —— 捕获的材料,永不修改 |
| **Wiki**(LLM 生成) | `Summary`(转述源)、`Entity`(名词)、`Concept`(综合的主张) |
| **Schema** | 本协议(`AGENTS.md`)—— 定义类型、关系、操作 |
| **Navigation** | `index`(目录)+ `log`(append-only 操作日志) |
| **Health** | `wiki-health`(MEASURE 快照,每个 loop 刷新) |

文件夹**不承载意义**——类型与关系承载。一个 Source 是否"已消化",看它的 `status: Digested`,不是它躺在哪个目录。

## 四种页面类型

| 类型 | 是什么 | 例子 |
|---|---|---|
| **Source** | 不可变的原始材料(文章、论文、记录、访谈) | 一项关于会议成本的研究 |
| **Summary** | 对一个 Source 的转述(TL;DR + 要点 + 引用) | 那项研究的摘要 |
| **Entity** | 一个名词——人、组织、工具、事件 | 某研究团队、某公司、Slack、2020 远程办公潮 |
| **Concept** | 跨多个 Source 综合出的**主张** | "对成熟团队,异步更新比每日站会更低摩擦" |

> **Concept 是知识库的灵魂。** 它不是对某个源的复述,而是从多个源提炼出的、可被新证据支持或推翻的主张。一个 Concept 只被一个 Source 提到时,是"单源、饥饿"的假设;被 ≥3 个 Source 提到,才算"成熟"。

## 关系图

```
Source  ──derived_into──▶  Summary
Summary ──source────────▶  Source
Summary ──mentions──────▶  Entity | Concept
Entity  ──mentioned_in──▶  Summary   ;   Entity ──related_to──▶ Entity
Concept ──related/contradicts──▶ Concept   ;   Concept ──mentioned_in──▶ Summary
```

每条关系双向维护:Summary 记 `mentions:`,被提及的 Concept 记 `mentioned_in:`。`mentioned_in` 的深度——一个主张被多少独立源支撑——是整套系统的**核心健康指标**。

## 闭环:维护飞轮

知识库靠闭环维护,不是一次性整理。每消化一个 Source,就跑完一圈:

```
        INGEST ──▶ MEASURE ──▶ LINT ──▶ PLAN
           ▲                            │
           └────────(下一篇 Source)──────┘
                          │
                    QUERY (随时)
                      ↓
                Open gaps ──▶ 反馈 PLAN
```

- **INGEST** —— 读 Source → 建/更新 Summary → 更新触及的 Entity/Concept → 标 Source `Digested` → 更新 index → 记 log。
- **MEASURE** —— 刷新 `wiki-health`:概念饥饿度(每个 Concept 的 `mentioned_in` 深度,目标 ≥3)、综合度、矛盾健康度、覆盖广度、漂移率、Query 复用率。
- **LINT** —— 找矛盾、过期 Summary、孤儿页、缺失的交叉引用、index 漂移;逐个修掉。
- **PLAN** —— 从 MEASURE + LINT + query gaps,挑下一个 Source。规则:**先喂最饥饿的 Contested Concept**——一篇既抬升深度、又可能顺手化解矛盾的源。
- **QUERY** —— 用知识库回答真实问题,带 `[[citations]]`。答不全的地方记进 Open gaps——**一次失败的 query,就是下一篇该去找什么的信号。**

**两个反馈源,都不静默**:① LINT 的结构问题,② query 的缺口。两者都留痕在 `wiki-health` 或 `log`。

### 为什么没有实时 dashboard(一个诚实的设计决策)

实时聚合仪表盘在这里**故意缺席**,且这是踩坑后的结论,不是疏忽:

- 运行环境(Tolaria、Obsidian)大多没有"按 frontmatter 聚合计数"的原生能力——saved views 能**筛选**,不能**统计**。
- 嵌在笔记里的 sandboxed JS 仪表盘,尝试用 `{{frontmatter}}` 取数,在多种环境下渲染不可靠。

所以方案是一个**诚实的组合**:一个周期刷新的静态 `wiki-health` 页(能算任意 KPI,但是快照)+ 两三个 saved views(只做 views *能* 做的事:按 `status` 筛、按空 `mentioned_in` 筛,且**实时**)。不假装实时,也不放弃可见性。

## 如何复用(三步)

1. **落 schema** —— 把 [`AGENTS.md`](./AGENTS.md) 放进知识库根目录;把 [`templates.md`](./templates.md) 里的类型定义建成类型页(或让 agent 创建笔记时 inline 用)。
2. **丢一个 Source** —— 扔进任何原始材料(文章 / 论文 / 记录),打 `type: Source, status: Unprocessed`。
3. **让 agent 跑 INGEST** —— 对 agent 说"按 AGENTS.md ingest 这个 source",或触发 `/ingest <file>`。它会建 Summary、更新 Concept、刷新 wiki-health、记 log。

第一个 Source 通常触及 10–15 个页面。**这是特性,不是 bug**——第一块石头落下,整座 cairn 就开始生长。

## 自动化(可选):连手动触发也省掉

不想每次手动跑 INGEST?`automation/auto-loop.sh` 是一个 inbox-pump 守护:把文件丢进 `inbox/`,它自动按 `AGENTS.md` 消化该源、并转一整圈 loop(MEASURE→LINT→PLAN)。

- 即时触发(fswatch),无 fswatch 时自动退化到 5s 轮询 —— 零依赖也能跑。
- 权限收口:默认只允许读写文件 + 检索,不给任意 shell。
- 你仍掌握"读什么"(往 inbox 丢什么),自动化所有机械活。详见 [`automation/README.md`](./automation/README.md)。

## 环境适配

协议与环境无关;变的只是适配层:

| 环境 | 适配方式 |
|---|---|
| **Tolaria** | 原生支持 type 系统 + saved views + wikilink。直接用 `views/*.yml`。参考实现。 |
| **Obsidian + Claude Code** | type 用 frontmatter + 模板;saved views 换 Dataview 或 `grep`。 |
| **纯文件夹 + 任意 agent** | 完全可用。saved views 换 `grep -l` / 小脚本;`mentioned_in` 深度用 `grep -c`。 |

核心协议(schema + 闭环)三者通用。失去的只是某个 app 的便利视图,不是方案本身。

## 目录结构

```
cairn/
├── README.md              ← 你正在读
├── AGENTS.md              ← schema 层:类型、关系、操作、闭环(agent 读这个)
├── templates.md           ← 四种类型的 frontmatter 模板 + wiki-health 模板
├── views/                 ← saved views(Tolaria 格式,其他环境作参考)
│   ├── contested-concepts.yml
│   ├── orphan-radar.yml
│   └── inbox.yml
├── examples/minimal/      ← 端到端最小示例(Source → Summary → Concept)
├── automation/            ← 可选:inbox-pump 守护,丢文件即自动消化 + 转 loop
│   ├── auto-loop.sh
│   └── README.md
└── LICENSE
```

## 局限(诚实声明)

- **不是 SaaS** —— 没有数据库、没有服务端、没有账号。文件即真相。
- **依赖 agent** —— 离开 LLM agent,这套协议只是纸面约定;它的价值在 agent 按 schema 自动执行。
- **健康页是快照** —— 不是实时。接受这点,别再试 sandboxed JS 仪表盘(试过,不可靠)。
- **单源 Concept ≠ 事实** —— 只被一个 Source 提到的 Concept 是"饥饿"的假设,不是已证实的结论。`mentioned_in` 深度告诉你该信几分。
- **n=1 时不证明 compounding** —— 知识库的价值,要等第二个、第三个 Source 进来、矛盾开始被 reconcile 时才显现。喂它几篇,再评判。

## 哲学

> 让 LLM 把"读过"变成"记住、连接、并随证据自我修正"——把知识从消耗品,做成会增值的资产。

## 致谢

- [Karpathy 的 LLM Wiki](https://karpathy.bearblog.dev/the-llm-wiki/) —— 原始思想。
- [Tolaria](https://github.com/refactoringhq/tolaria) —— 参考实现的运行环境(files-first、git-first、type 系统)。

## License

MIT —— 见 [LICENSE](./LICENSE)。拿去用,改了更好,欢迎反馈。
