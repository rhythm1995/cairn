# Templates — 页面类型与 frontmatter

> 复制这些模板建类型页 / 新笔记。frontmatter 字段是 **schema**;body 结构是**约定**。
>
> - **Tolaria**:把每个类型建成一个 `type: Type` 的"类型文档",空字段会成为新笔记的占位符,默认值会自动套用。
> - **其他环境**:把 frontmatter 当 inline 模板,agent 创建笔记时套用即可。

---

## Source(不可变源)

```yaml
---
type: Source
status: Unprocessed          # Unprocessed → Digested
derived_into:                # ingest 后设为 [[the-summary]]
url:                         # 可选,原始来源链接
date: <YYYY-MM-DD>           # 可选,源本身的日期(不是捕获日期)
---
```

body 就是原始材料本身。**永不编辑已捕获的 Source** —— 重新消化产出新 Summary,旧的标 `Superseded`。

---

## Summary(转述一个源)

```yaml
---
type: Summary
source: "[[the-source]]"
status: Active               # Active → Superseded
generated: <YYYY-MM-DD>      # 消化日期,纯日期,不要时间戳
mentions:                    # 本 Summary 触及的所有 Entity/Concept(ingest 时回填)
  - "[[concept-...]]"
  - "[[entity-...]]"
---
```

body 骨架:

```markdown
# Summary — <标题>

## TL;DR
<2–4 句,这篇源的核心>

## Key points
- <要点,每条带 [[concept/entity]] 链接>

## Quotes
> <逐字引用,带归属>
```

---

## Entity(名词)

```yaml
---
type: Entity
entity_kind: org             # org | person | tool | event | concept-term ...
aliases:                     # 可选,别名/旧称
mentioned_in:                # 提到它的所有 Summary —— 深度随源增长
  - "[[summary-...]]"
---
```

body 骨架:`## What` / `## Why it matters` / `## Facts`(每条带 `[[summary]]` 引用)。

---

## Concept(综合的主张)— 知识库的灵魂

```yaml
---
type: Concept
status: Active               # Active;加了 contradicts → Contested;化解后回 Active
definition: "<一句话主张>"
related:                     # 相关(不矛盾)的 Concept
  - "[[concept-...]]"
contradicts:                 # 矛盾的 Concept(加了就设 status: Contested)
  - "[[concept-...]]"
mentioned_in:                # 提到它的所有 Summary —— 深度即可信度,目标 ≥3
  - "[[summary-...]]"
---
```

body 骨架:

```markdown
# <Concept 名>

## Definition
<展开 frontmatter 的 definition>

## Evidence
<按来源分小节,各带 [[summary]] 引用>

## Tensions
<与其他 Concept 的张力/边界条件>

## Reconciliation 记录
<若有矛盾被化解:谁、何时、因什么证据。留痕。>

## Open questions
<未决的、待下一篇源回答的>
```

> **Concept 的可信度 = `mentioned_in` 深度。** 深度 1 = 单源假设(饥饿);≥3 = 成熟。永远不要把单源 Concept 当事实陈述。

---

## index(目录)

```yaml
---
type: Note
_order: 0
visible: true
---
```

body:`## Sources` / `## Summaries` / `## Entities` / `## Concepts` 分类的 wikilink 列表。每次 ingest 更新;`lint()` 保持无漂移。Concept 段建议按 `mentioned_in` 深度排序,达标(≥3)标 ✅。

## log(append-only 操作日志)

```yaml
---
type: Note
_order: 1
visible: true
---
```

body:每行一个操作,最新在底,**永不编辑旧行**(改正追加在下方):

```
- YYYY-MM-DD ingest [[source]] → [[summary]] (+N entities, +M concepts)
- YYYY-MM-DD loop MEASURE+LINT+PLAN: <一句话决策>
- YYYY-MM-DD lint <finding> → <fix>
```

## wiki-health(MEASURE 快照)

```yaml
---
type: Note
_order: 2
visible: true
---
```

body:每次 `/wiki-loop` 由 agent 刷新(**静态快照,非实时**)。建议章节:

- 顶部:`Last measured: <YYYY-MM-DD> (<第 N 次 loop>)`
- `## 本轮成果` —— 本次 ingest/query 后的 delta,带 ✅
- `## KPI`(表):Sources、Summaries、Concepts、Entities、平均 `mentioned_in` 深度、达标 Concept(≥3)数、single-source 占比、矛盾健康度、覆盖广度、漂移率、Query 复用率
- `## 概念饥饿度`(表):每个 Concept 的 深度 / status / 还需
- `## 本轮决策(PLAN)` —— 下一个 Source + 依据
- `## 配套的活切片` —— 指向 saved views
- `## Open gaps` —— query 答不全时记,驱动下一篇
