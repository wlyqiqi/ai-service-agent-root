# 执行计划（docs/plans/）

> **归档索引**：本目录为历史实现计划，正文一般不改写。现行行为以 `docs/specs/` 与 `docs/adr/` 为准。C 端主入口见 [ADR 0001](../adr/0001-widget-agentbot-form-contract.md)（自建 SSE 用户页已废止）。

- `2026-09-14-mvp-first-mile.md` — MVP 第一公里实现计划（Task 0–9，TDD，每任务可独立测试与 commit），对应 `docs/specs/mvp-first-mile.md`（历史里程碑）。
- `2026-09-15-p3-guard-mutation-highrisk.md` — P3 Guard / Mutation / HighRisk / Approval 实现计划（Task 1–8，TDD，每任务 commit）。
- `2026-09-15-p4-clarify-precheck-resume.md` — P4 Clarify / 预检规则增量 / 读侧边界 / resume final 提取 实现计划（Task 1–6，TDD，每任务 commit）。
- `2026-09-17-user-page-frontend.md` — ~~自建 SSE 用户页前端~~（历史；对应已废止 `user-page-spec.md`）。**勿再按此实现**；C 端见 ADR 0001。
- `2026-09-18-user-page-backend-integration.md` — ~~用户页 ↔ 后端契约~~（历史；对应已废止 `user-page-spec.md` §10/§11）。人工车道真机验收改走 `scripts/real_human_lane_smoke.py` 等。
- `2026-09-18-handoff-intent-gate.md` — P0 显式转人工入口检测（detector 前置拦截，不进 Router/Guard/Graph）+ 统一 `_emit_handoff` side-effect path（Task 1–5，TDD，每任务 commit）。
- `2026-09-18-readgraph-lightrag-rag.md` — ReadGraph 知识库 RAG 接入（`kb_search` 接真实 LightRAG-chengyuan 检索：`naive` / 关 rerank / 来源标注 / 确定性降级 / 真机冒烟）（Task 1–5，TDD，已完成）。

### 其余计划（归档，按日期）

9 月批次：

- `2026-09-14-p1-checkpointer-resume.md` — P1 Checkpointer 持久化与 Handoff 恢复。
- `2026-09-14-p2-tools-and-evals.md` — P2 工具注入 + 离线评估基线。
- `2026-09-16-ctrl-0076-clarify-verification.md` — CT-RL-0076 Clarify 验证收尾。
- `2026-09-16-p5-select-tier-alignment.md` — P5 Select 工具风险对齐。
- `2026-09-17-chatwoot-handoff-integration.md` — Chatwoot 坐席端接入。
- `2026-09-17-mutation-tools-refactor.md` — Mutation 工具集重构。
- `2026-09-19-chatwoot-agent-context-sync.md` — Chatwoot Agent Context Sync。
- `2026-09-20-cancel-order.md` — Cancel Order。
- `2026-09-21-refund-apply.md` — refund_apply。
- `2026-09-22-harness-tool-hook.md` — Harness Tool Hook MVP。
- `2026-09-22-sqlite-jwt-auth.md` — SQLite JWT Auth MVP。
- `2026-09-23-cs-tone-copy.md` — Customer-Service Tone Copy Layer。
- `2026-09-23-jev-route-intent-policy.md` — Jev Route Intent Policy。
- `2026-09-24-jev-route-precision.md` — JEV Route Precision。
- `2026-09-24-select-bind-tools-refactor.md` — Select 节点 `bind_tools` 重构。
- `2026-09-25-langgraph-fault-tolerance.md` — LangGraph Fault Tolerance。

10 月批次（状态以各文件头部为准）：

- `2026-10-19-form-gate-deep-module.md` — Form Gate 深模块（已实现）。
- `2026-10-19-handoff-request-created-flag.md` — Handoff Request 幂等来源收敛（已实现）。
- `2026-10-20-approval-side-channel-deep-module.md` — Approval Side-Channel 深模块（已实现）。
- `2026-10-28-seat-approval-card.md` — 坐席端审批卡方案（已实现，ADR-0006 / PR #144）。
- `2026-10-28-seat-approval-execution-plan.md` — 坐席端审批卡执行计划（部分实现，T10 未做）。
- `2026-10-29-thread-idle-reaper.md` — Thread 空闲回收 #151（已实现）。
- `2026-10-29-thread-rotation.md` — 安全边界上的自动 thread 轮换 #150（已实现）。

- 计划按 superpowers:writing-plans 规范编写；新功能请先改 specs/ADR，再开计划，勿直接以本目录旧计划为权威。
