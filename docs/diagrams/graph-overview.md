# CustomerServiceGraph 总图（AI 路径内部结构）

> 权威定义：`docs/specs/graph-spec.md`、`docs/specs/handoff-spec.md`。
> 顶层会话流程见 `handoff-overview.svg`。Archify 渲染版见 `架构图/archify-architecture.html`。

```mermaid
flowchart TD
    A["新消息"] --> B{"conversation_mode == human ?<br/>Conversation Runtime（轻量）"}
    B -- "是(human)" --> H["human 车道（AI 暂停）<br/>写 Message Store，通知坐席"]
    B -- "否(ai)" --> C{"存在挂起 interrupt ?<br/>入口层 aget_state 读 __interrupt__"}
    C -- "是" --> R["入口层 resume 调度<br/>Command(resume=...) 续接子图"]
    R --> RG["恢复至被中断子图<br/>不重走 Router"]
    C -- "否" --> G["Guard ∥ Router<br/>并行；Router 产出 route_intent + confidence"]
    G --> P["Policy Gate<br/>route_intent → target_graph / allowed_tools / …"]
    P --> SF["safety_final<br/>Guard fail"]
    P --> RD["ReadGraph<br/>ReAct + 只读工具"]
    P --> MU["MutationGraph<br/>select（tool 或 Operation Clarify）→ 预检 → Form Interrupt → 执行"]
    P --> HR["HighRiskGraph<br/>select → 预检/Form → 审批 interrupt"]
    P --> CP["ComplaintGraph<br/>安抚 + 询问是否转人工（不自动 handoff）"]
    P --> FB["Fallback<br/>unknown / 兜底"]
    SF & RD & MU & HR & CP & FB --> F["Final Response<br/>写回 messages + 归一化事件"]
    RD & MU & HR & FB --> HO["interrupt(handoff_request)<br/>外层：建/复用 awaiting_seat + handoff_requested<br/>execution_status=waiting_handoff；mode 仍为 ai"]
    HO --> Q["Chatwoot 人工队列<br/>handoff-request tag + private note<br/>open → round_robin"]
    Q --> T["Seat Takeover<br/>open + User assignee"]
    T --> H["human 车道<br/>active handoff + mode=human + handoff_created"]
    HR -. "approval_required" .-> AP["Seat Approver<br/>Approval Side-Channel private card"]
    AP -. "approve / reject → Runtime resume<br/>conversation_mode 不变" .-> HR
    H --> RESOLVE["人工 Resolve<br/>校验 pending 审批 → mode=ai<br/>handoff_resolved"]
    RESOLVE --> A
    F --> PRE{"发送前重校验 mode == ai ?<br/>读实时值"}
    PRE -- "是(ai)" --> SEND["通过 SSE / AgentBot 发送"]
    PRE -- "否" --> DROP["丢弃（防双重回复）"]
```

## 关键注记

- Guard 为确定性规则包（与 Router 并行）；fail 走 `safety_final`，不消费 Router 分类结果做子图路由。
- Router 唯一语义输出是 `route_intent` + `confidence`；子图选择由 Policy Gate 确定性派生（见 `state-spec.md`）。
- Mutation 主路径用 Form Interrupt（`form_required`），不是聊天 `confirmation_required`；tool 未定由 Mutation `mutation_select_llm` 内联 Operation Clarify（ADR 0004），无入口 Hybrid。HighRisk 工具选择为 `high_risk_select_llm`（ADR 0005）。
- Handoff Request 只挂起并创建/复用 `awaiting_seat` 记录，`mode` 保持 `ai`；Chatwoot 队列 round-robin 后，`open + User assignee` 触发 Seat Takeover，才进入 human 并发出 `handoff_created`。
- Approval Side-Channel 与 Seat Takeover 相互独立：审批卡/decision 只恢复 HighRiskGraph，不切换 `conversation_mode`（ADR-0002 / ADR-0006）。
- ComplaintGraph 不挂 Fallback，也不走 Concierge `explain_llm`；Complaint 只安抚并询问是否转人工。
- Form / 审批挂起时父图 `execution_status` 常仍为 `routing`；对外权威是 checkpointer `__interrupt__`。
- `conversation_id=session_id`；`thread_id` 是 LangGraph checkpoint 标识，不是同一字段。thread 惰性创建、可在安全边界轮换；pending interrupt 与活跃 handoff/审批会固定 thread，ThreadReaper 由离线 CLI 与 FastAPI lifespan 共用（见 `thread-lifecycle-spec.md`）。
