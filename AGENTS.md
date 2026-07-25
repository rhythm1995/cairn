# AGENTS.md — Cairn schema layer

> Agent 读这个。它定义页面类型、关系、以及让知识库自我维护的操作协议。
> README 讲哲学;本文件讲怎么干。把这个文件放进知识库根目录。

## Layering

| 层 | 在本知识库里的形态 |
|---|---|
| Raw(不可变源) | `Source` 类型 |
| Wiki(LLM 生成) | `Summary`、`Entity`、`Concept` |
| Schema | 本文件 |
| Navigation | `index`(目录)+ `log`(append-only 操作日志) |
| Health | `wiki-health`(MEASURE 快照,每个 loop 刷新) |

**文件夹不承载意义。** 类型(`type:`)与关系(`[[wikilinks]]`)承载意义。一个 Source 是否"已消化"由 `status: Digested` 决定,不由它放在哪个目录决定。

## 页面类型

四种核心类型(模板见 `templates.md`):

- **Source** —— 不可变的原始材料。捕获后永不修改;重新消化产出*新的* Summary,旧的标 `Superseded`。
- **Summary** —— 对单个 Source 的转述。必含 `source:` 链接、`## TL;DR`、`## Key points`、`## Quotes`、`mentions:` 列表。
- **Entity** —— 一个名词(人/组织/工具/事件)。记 `mentioned_in:`。
- **Concept** —— 跨多个 Source 综合出的**主张**。这是知识库的灵魂;其可信度随 `mentioned_in` 深度增长。

### 状态机

- **Source.status**: `Unprocessed` → `Digested`(ingest 后)
- **Summary.status**: `Active` → `Superseded`(其 Source 被重新消化时)
- **Concept.status**: `Active`;一旦加了 `contradicts:` 链接 → `Contested`;矛盾化解 → 回 `Active`(并在页内留 Reconciliation 记录)

## 关系图

```
Source  ──derived_into──▶ Summary
Summary ──source────────▶ Source
Summary ──mentions──────▶ Entity | Concept
Entity  ──mentioned_in──▶ Summary ; Entity ──related_to──▶ Entity
Concept ──related/contradicts──▶ Concept ; Concept ──mentioned_in──▶ Summary
```

每个关系**双向维护**:Summary 的 `mentions:` 列出它触及的所有 Entity/Concept;每个被提及的页在自己的 `mentioned_in:` 里回指该 Summary。`mentioned_in` 深度是核心健康指标(目标 ≥3)。

## 原则

1. **Compounding artifact** —— 知识库建一次,持续更新。不要在每个问题上从源重新派生。先读已有页。
2. **Sources are immutable** —— 永不编辑 Source。重新消化产出新 Summary,旧的标 `Superseded`。
3. **Your own words** —— Summary 转述;Entity/Concept 综合。逐字引用只在 `## Quotes` 下,带归属。
4. **Cite everything** —— 每个 claim 链接它的 Summary(从而 Source)。
5. **One Source ↔ ≥1 Summary** —— Source 不算完成,直到 `status: Digested` 且 `derived_into` 已设。
6. **单源 Concept ≠ 事实** —— 只被一个 Source 提到的 Concept 是饥饿的假设,不是结论。

## 操作

### Ingest — `ingest(source)`

触发:新 Source 加入,或 `/ingest <file>`。

1. 通读 Source。
2. 建(或更新)`Summary`:设 `source: [[the-source]]`;写 `## TL;DR`、`## Key points`、`## Quotes`;设 `status: Active`、`generated: <YYYY-MM-DD>`。
3. 设 Source 的 `status: Digested`,`derived_into: [[the-summary]]`。
4. 对每个值得记的 entity/concept:建或更新其页;把本 Summary 加进它的 `mentioned_in`;在 Concept 上,只要加了 `contradicts:` 就设 `status: Contested`。
5. 回填 Summary 的 `mentions:` 列表(第 4 步触及的所有 Entity/Concept)。
6. 更新 `index` —— 在对应分类下加新页。
7. 往 `log` 追加一行:`- <YYYY-MM-DD> ingest [[source]] → [[summary]] (+N entities, +M concepts)`。
8. 刷新 `wiki-health` —— 从当前知识库状态重算 KPI 与概念饥饿度表(即 MEASURE,见 `### Loop`)。

一个 Source 通常触及 10–15 页。**这是特性,不是 bug。**

### Query — `query(question)`

触发:用户问知识库能答的事。

1. 读 `index` 找候选 Summary/Entity/Concept。
2. 打开最相关的;按需跟 wikilink。
3. 综合**带引用**的答案 —— `[[page]]` 或 `[[page|§section]]`。
4. 答案若可复用,提议存为新 `Concept`(claim)或 `Summary`。
5. 若知识库无法完整回答(缺 Source、单源 Concept 被当事实、未经检验的 claim),记录缺口:在 `wiki-health` § Open gaps 下追加一条。**失败的 query 是下一篇该 ingest 什么的信号** —— 它喂 PLAN。

### Lint — `lint()`

触发:周期性,或 `/wiki-lint`。

1. **矛盾** —— 有 `contradicts:` 的 Concept;核实双方是否仍成立,标出未决的。
2. **过期** —— Source 被重新消化过的 Summary;旧的标 `Superseded`。
3. **孤儿** —— `mentioned_in` 为空的 Entity/Concept;合并或删除。
4. **缺失交叉引用** —— 正文里提到了已知 Entity/Concept 但不在 `mentions:` 里的 Summary;回填。
5. **Index 漂移** —— index 漏掉的页,或指向已删页的 index 条目。
6. 每个修复追加进 `log`,记作 `lint …`。

### Loop — `loop()`

知识库是飞轮,不是一次性操作。每次 ingest 都闭环:**INGEST → MEASURE → LINT → PLAN**,PLAN 选下一个 Source。触发:每次 `ingest` 结束,或 `/wiki-loop`。

1. **MEASURE** —— 用当前 KPI 刷新 `wiki-health`:
   - **概念饥饿度** —— 每个 Concept 的 `mentioned_in` 深度,目标 ≥3。**头条指标**;它驱动下一个 Source 的选择。
   - **综合度** —— 单源 Concept 数;平均 `mentioned_in` 深度。
   - **矛盾健康度** —— Contested Concept 数,拆成已 reconcile vs 未决。
   - **覆盖广度** —— 每个 Entity 的 Source 数;主题聚类(盲区在哪)。
   - **漂移率** —— lint 发现(孤儿/漂移/缺交叉引用);目标 0。
   - **Query 复用率** —— 命中已有 Concept 的答案,或被存回为新页的答案。
2. **LINT** —— 跑上面的 `lint()`;其发现(孤儿、未决矛盾、漂移)是 PLAN 的结构反馈。
3. **PLAN** —— 从 MEASURE + LINT + 任何未决 query 缺口,决定下一个要 ingest 的 Source。规则:**先喂最饥饿的 Contested Concept** —— 它同时抬升深度 *并可能* 在一步内化解矛盾。把决策写进 `wiki-health` § 本轮决策。
4. **INGEST** —— 选定的 Source。完成后,MEASURE 再跑一次(第 1 步)。闭环。

**两个反馈源喂 PLAN,都不静默**:① LINT 的结构问题,② query 缺口(记在 `wiki-health` § Open gaps)。两者都在 `wiki-health` 或 `log` 留痕。

> **不要尝试 in-note JS dashboard。** 本方案不依赖、也不追求实时聚合(见 README § 为什么没有实时 dashboard)。`wiki-health` 是周期刷新的快照;saved views 是实时但只能筛选的补充。sandboxed HTML 在多数环境解析 `{{frontmatter}}` 不可靠。

## Agent 默认行为

- 类型优先于文件夹结构。
- 拿不准类型时:捕获的材料默认 `Source`,综合的主张默认 `Concept`。
- 用 Inbox / Unprocessed 视图找 `status: Unprocessed` 的 Source。
- 日期用 `YYYY-MM-DD`。**不要发明时间戳** —— 用用户给的日期,或问。
- 多源命中同一个 Concept 时,合并视角而不是各写一段;在 Concept 页里按来源分小节并各留 `[[summary]]` 引用。
