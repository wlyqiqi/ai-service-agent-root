# 文档新鲜度审计（2026-11-06）

> 审计阶段只读。范围：`git ls-files` 跟踪的 **149 个 .md**，对照 **577 个 commit** 的 author date、文件内容引用与 `src/` 实装代码。
> 方法脚本：`tmp/audit_docs.py`；原始指标：`tmp/doc_audit_raw.json`（均为本地临时文件）。
> **修复状态**：P0 / P1 已按 §1 / §2 在 `docs/freshness-p0-p1` 分支处理（2026-11-06）；P2 保留为后续低频维护。下文问题描述是审计当时的快照。

## 结论

| 级别 | 数量 | 含义 |
|---|---|---|
| P0 | 3 | 内容会把实现/运维带偏，需尽快改 |
| P1 | 5 | 状态字段、索引、断链陈旧，影响可读性 |
| P2 | 3 | 长期未动的归档/静态资料，建议复核 |
| 非问题 | — | 已显式标注废止/快照的文档，见 §4 |

**整体判断**：现行 `docs/specs/` 核心与 `docs/adr/` 更新节奏良好（多数 0–14 天）。问题集中在**三处接缝**：ADR 之间的修订回指、spec 的实现度标注、以及历史计划/决策目录的索引纪律。

---

## 1. P0 — 内容与代码冲突

### 1.1 `docs/adr/0003-seat-gated-handoff.md` 未回指 ADR-0007

- 最后修改 2026-10-16（21 天）。Amendment 段写：**"Bot / 客户路径不得 `toggle_status(open)`"**（文件末段）。
- `docs/adr/0007-handoff-auto-round-robin.md`（2026-11-03，PR #156，accepted）Consequences 明写：**"本决策替代 ADR-0003 中『Handoff Request 不得改变 Chatwoot status』的部署细则"**；Decision 第 4 条要求 Runtime 用 AgentBot token 调官方 `toggle_status(open)` 触发 `bot_handoff!`。
- `docs/specs/handoff-spec.md` 已于 11-03 同步（第 29、72 行）。**只有 ADR-0003 没同步**。
- 风险：只读 0003 的人会得到与现行部署相反的禁令。

**改法**：0003 头部加一行 `> Superseded in part by ADR-0007 (2026-11-03)`；Amendment 末段那条改为「除 ADR-0007 自动轮询部署外，Bot / 客户路径不得 `toggle_status(open)`」。

### 1.2 `docs/specs/safety-spec.md` §2.1 把未实现的触发规则写成现行规则

- §2.1 触发表列 7 类：路由/兜底连续失败、工具级连续失败、重复未解决、情绪信号、审批被拒后坚持、显式请求、策略上限。
- `src/ai_service_agent/graph/workflows/fallback.py::check_handoff` 实际只判 **2 类生效**：`fallback_count >= fallback_max_turns`（第 53 行）、图内 `detect_handoff_intent`（第 63 行）。情绪分支存在但 `_emotion_signal()` **恒返回 `False`**（第 30–33 行，注释「PR-A 不启用」）。工具级失败计数、`clarify_count` 接 handoff、审批拒绝后坚持、策略上限均未落地。
- 第 85 行：**"动态信号（连续失败 / 情绪 / 审批被拒后坚持等）仍由图内 `check_handoff` 判定"** — 错误陈述。
- 文件头只有 `状态：**新增**`，没有实现度标注；最后修改 2026-10-26（PR-A 之后未再同步）。

**改法**：§2.1 表格加「实现状态」列，未实现项标 `未实现 / 待排期`；第 85 行「仍由」→「规划由」；第 98 行「后续应复用」保留未来时态并显式标注未实现。

### 1.3 `PRODUCT.md` 的硬约束已被后续 PR 推翻

- 2026-10-09，28 天，1 commit。第 17 行：**"Do not modify the Chatwoot/WootChat widget, APIs, message handling, or interaction logic"**；第 12、18 行称 widget 为 **immutable black box**。
- 之后已落地：`widget-commercial.css`（#145）、Z2 CSS 覆盖（#139/#141）、注入 `docs/ops/chatwoot/seat-approval.js`（#144 / ADR-0006）、ADR-0007 改 conversation status（#156）。
- 第 24 行 "existing static frontend entrypoint"：原 `web/index.html` 已随 `user-page-spec.md` 废止移除，现为 `web/landing.html` / `landing-v2.html`。
- 仍准确的部分：`/auth/login`（`server.py:805`）、`/sessions`（`server.py:866`）确实存在。

**改法**：第 12/17–18 行改为「Widget 为 Chatwoot 托管、不 fork 镜像；视觉与坐席端通过 CSS/JS 覆盖，见 `docs/ops/chatwoot-widget-form.md` 与 ADR-0006」；第 24 行更新入口文件名。

---

## 2. P1 — 状态、索引、断链

| # | 文件 | 问题 | 改法 |
|---|---|---|---|
| 2.1 | `docs/plans/2026-10-19-form-gate-deep-module.md:4` | 头部 `状态：待评审`，但文末 §实现记录已写 Phase 1 ✅ `8d941ca2`、Phase 2 ✅ `a34f2617`，且 `src/ai_service_agent/harness/form_gate.py::decide_form_inbound` 已落地。状态与正文/代码自相矛盾，18 天未改 | 头部改 `已实现`，指向文末实现记录 |
| 2.2 | `docs/plans/2026-10-28-seat-approval-card.md:3` | `状态：**方案（未实现）**`，但 ADR-0006 accepted、PR #144 已合、`docs/ops/chatwoot/seat-approval.js` + `.css` 已存在，配套执行计划 §9 写「T1–T9 已实现（T10 未做）」。违反项目约定「实现后改状态并补实现记录」 | 头部改 `已实现（PR #144，T10 未做）` |
| 2.3 | `docs/plans/2026-10-28-seat-approval-execution-plan.md` | 无状态字段；§9 有实现记录（T1–T9 已实现、T10 未做），头部未反映 | 头部补 `状态：部分实现` + 指向 §9 |
| 2.4 | `docs/plans/README.md` | 自称归档索引，实际只登记 **7 / 30** 个计划，**23 个未登记**，含 10 月全部产出（form-gate、handoff-request-created-flag、approval-side-channel、seat-approval-\*、thread-\*）。最后 2026-10-21（16 天） | 补齐索引，或明确写「仅索引 9 月计划，其余见 git log」 |
| 2.5 | `AGENTS.md` §5、`docs/specs/README.md`、`CONTEXT.md`、根 `README.md` | 四份入口文档**均未出现** `0006` / `0007` / `seat-approval.js` / `chatwoot-widget-form.md`。AGENTS.md §5 的 ADR 行只到 0001/0003；新增 ops runbook（`chatwoot-widget-form.md`、`chatwoot-z2-form-echo-hide.md`、`thread-checkpoint-cleanup.md`）无索引行。另 AGENTS.md 第 40 行「决策记录见 `docs/decisions/`」与 `docs/agents/domain.md` 的「新决策优先 `docs/adr/`」不一致 | AGENTS.md §5 增补 ADR-0006/0007 与 ops runbook 行；`docs/decisions/` 标注为归档 |

### 现行文档的断链（3 处需修）

| 文件 | 引用了不存在的路径 |
|---|---|
| `docs/specs/mutation-form-interrupt-spec.md:15` | `docs/plans/2026-10-15-mutation-form-ux-implicit-cancel.md` |
| `docs/ops/seat-gated-handoff-live-checklist.md` | `docs/manual-e2e-fullchain-test-cases.md`（另 `live-smoke-...YYYY-MM-DD.md` 为模板占位，可忽略） |
| `docs/real-model-smoke.md` | `web/index.html`（历史路径引用，指向已废止的自建 SSE 用户页） |

另有 **26 个文档共含断链**，其余集中在 9 月历史 plans / `docs/superpowers/plans/`，引用 `tests/test_user_page.py`、`web/index.html`、`tests/evals/control/*.json` 等已移除或改名的文件；按 `docs/plans/README.md` 的归档定位可不动，但建议在这些文件头加一行「历史归档，路径引用可能失效」。

> 附带：`AGENTS.md` §2 要求「改图 / 换 API 前读 `docs/project-audit.md`（尤其 B 节）」，而该文件是 2026-09-11 快照、头部已声明「不是现行架构说明」。建议把措辞收窄为「B 节仅作 API 版本考古，现行以 `pyproject.toml` + 已安装包为准」。

---

## 3. P2 — 长期未更新（归档/静态，非缺陷）

| 项 | 数据 | 建议 |
|---|---|---|
| `knowledge-base/` 34 个文档 | 全部 2026-09-12 创建，**55 天未动、各 1 commit**；frontmatter 统一 `version: 1.0` / `status: active` | 静态业务资料合理。但 `08_知识缺口/知识缺口说明.md` §5 要求「随每次知识库审核复核」，而 10 条 GAP 仍全部「未定义」，`知识库审计报告.md` 同日 1 commit → 做一次复核并留痕 |
| `docs/decisions/` 17 个文件 | 2026-09-11 ~ 10-10，最老 56 天，多为 1 commit | 事实已被 `docs/adr/` 取代，但目录无 README 说明。加一个归档声明即可 |
| 单 commit 文档 | **96 / 149（64%）** | 主体是 plans / decisions / reports / knowledge-base，属归档性质，不需要逐个刷新 |

**年龄分布**：最老 `docs/decisions/2026-09-11-spec-audit-and-fixes.md`（56 天）；9 月计划群 43–53 天；现行 specs 多在 0–14 天。项目本身只有约 2 个月历史，不存在「多年未更新」的文档。

---

## 4. 明确不是问题（避免误报）

三处已用头部声明处理得很好，审计中**不计入**问题：

- `docs/project-audit.md:3-6` — 「历史审计快照（2026-09-11），不是现行架构说明」，并给出权威指向。
- `docs/specs/user-page-spec.md:4` — 「已废止（2026-10-14）」，`docs/specs/README.md:20` 与 `docs/plans/README.md:3` 均有交叉标注。
- `docs/plans/README.md:3` — 「归档索引，正文一般不改写，现行行为以 specs/ADR 为准」。

同步及时的：`docs/specs/architecture.md`、`graph-spec.md`、`docs/diagrams/graph-overview.md`（今天 PR #4 同步）；`handoff-spec.md`（11-03 同步 ADR-0007）；`README.md`（11-04）；`state-spec.md` / `tool-spec.md` / `event-spec.md` / `approval-spec.md` / `safety-spec.md` 10 月下旬密集更新（内容问题见 §1.2）。`docs/specs/README.md` 的文件地图覆盖 **12 / 12** 个 spec 文件，完整。

---

## 5. 建议动作顺序

1. 先修 P0 三处（ADR-0003 回指、safety-spec 实现度列、PRODUCT.md 约束）— 都是局部文案改动，可一个 PR 收口。
2. 再修 §2 的状态字段 + `plans/README.md` 索引 + 3 处现行断链 — 第二个 PR。
3. `knowledge-base/` 复核与 `docs/decisions/README.md` 归档声明作为独立低频维护，不必跟车。
