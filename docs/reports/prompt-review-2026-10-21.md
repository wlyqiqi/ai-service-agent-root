# LLM 节点提示词评审（2026-10-21）

评审范围：`src/ai_service_agent/prompts.py` 及四处消费点。Guard / clarify / copy 为确定性文案，不在 LLM 提示词范围。

## 0. 结论速览

| 节点 | 提示词 | 位置 | 主要问题 | 优先级 |
|---|---|---|---|---|
| `router_deepseek` | `ROUTE_INTENT_SYSTEM` | prompts.py:99 | 输出契约双轨；11 个平行标签无决策顺序；confidence 无锚点且被阈值改写标签 | P0 |
| `select_llm` | `SELECT_SYSTEM_TEMPLATE`（仅 fake）/ `SELECT_BINDTOOLS_SYSTEM`（真实） | prompts.py:110 / 169 | 真实路径丢弃示例与参数契约；两条提示词语义相反；`tool_choice="any"` 结构性逼硬凑 | P0 |
| `agent_llm`（ReadGraph） | `READ_SYSTEM_PROMPT` | prompts.py:183 | 工具返回成品话术与提示词冲突；缺「禁止承诺」「一次一问」「能力边界」 | P0/P1 |
| `explain_llm`（Fallback） | `FALLBACK_SYSTEM_PROMPT` | prompts.py:200 | 不知道自己是哪类兜底；与 `check_handoff` 自动转人工形成双路径 | P1 |

一句话：**提示词本身的写作质量不差（规则具体、有边界意识），主要损耗在「提示词与代码路径不一致」——写得最好的那版没有在生产上跑。**

---

## 1. 现状：四个 LLM 节点

| 节点 | 真实模型调用方式 | temperature | max_tokens | 备注 |
|---|---|---|---|---|
| router | `with_structured_output(RouteIntentSchema, method="function_calling")`（router.py:223） | 0.0 | 256 | JEV 主路由，失败/低置信落此节点 |
| select | `bind_tools(tier_tools, tool_choice="any")`（select.py:224） | 0.0 | 512 | 写图唯一工具选择闸 |
| read agent | `create_agent` + 只读工具集（read_agent.py:44） | 0.3 | 1024 | ReAct 循环，调用上限 3 |
| fallback | `create_agent(tools=[])`（fallback.py:88） | 低 | 512 | 无工具，仅出文案 |

### 关键事实：select 有两条互斥的提示词路径

```
select.py:284  messages = _budgeted_select_messages(..., SELECT_SYSTEM_TEMPLATE.format(tool_list, examples))
select.py:292  if is_fake:  → 用上面这条（含工具清单 + 参数契约 + 业务示例）
select.py:301  else:        messages = _budgeted_select_messages(..., SELECT_BINDTOOLS_SYSTEM)
                            → 丢弃 tool_list 和 examples，换成 7 条短规则
```

`tool_list`（含 `参数：order_id(必填)，reason(可选)` 契约，select.py:33-42）和 `_build_examples`（真实业务话术 + schema 对齐参数 + 缺参示例，select.py:44-95）在真实模型路径上被完整计算出来、然后丢弃。**示例是参数抽取准确率最高杠杆的手段，现在只服务离线 fake 测试。**

---

## 2. P0 问题

### P0-1 真实路径丢弃示例与参数契约

`SELECT_BINDTOOLS_SYSTEM` 只有 7 条规则，没有任何示例，也没有 `参数：xxx(必填/可选)` 契约。工具 schema 由 `bind_tools` 下发给模型，字段名有了，但「用户这句话该怎么映射成参数」没有任何示范。

后果：参数抽取质量依赖模型自由发挥，而 `_normalize_placeholder_args`（select.py:112）要专门处理 `"null"` / `"暂无"` / `amount=0` 这类占位符——这本身就是「模型缺示例时乱填」的症状。

修法：真实路径也用 `SELECT_SYSTEM_TEMPLATE` 的 `tool_list` + `examples` 段落，只是保留 `bind_tools` 的 tool_call 返回格式（不要再要求 JSON 字符串）。

### P0-2 两条 select 提示词语义冲突

| 规则 | fake 版（prompts.py:152-155） | 真实版（prompts.py:179） |
|---|---|---|
| 用户请求不在工具集内 | 「只能从当前允许的工具中选择」「不要强行映射到其它工具」 | 「选择最接近的工具；系统会校验并拒绝不匹配的请求」 |

真实版在教模型硬凑。叠加 `tool_choice="any"`（select.py:224）强制必须产出一个 tool_call，模型没有「都不合适」的出口。

这会污染下游语义：
- `tier_clarify`（select.py:356-358）靠「选中了低档工具」推断风险档不匹配。硬凑出来的低档工具会被误判成「意图与风险档不符」，而不是「模型在瞎猜」。
- `_reject(..., "unknown_tool")` 与 `safety_rejected` 事件的可观测性被稀释。

修法（两处配套）：① 删掉「选最接近的工具」；② `tool_choice` 改 `"auto"`，无 tool_call 时按 `tier_clarify` / operation clarify 处理，而不是 `_reject("select_parse_failed")`（select.py:307-308）。

### P0-3 Router 输出契约双轨，且阈值会改写标签

- `ROUTE_INTENT_SYSTEM` 末尾给了 `输出格式：{"route_intent":"unknown","confidence":0.20}`（prompts.py:106-108），但真实路径走 `with_structured_output(function_calling)`，格式由 schema 保证。这段 JSON 指令对真实路径是冗余噪声（对 fake 路径必要）。建议按路径拆分，或改成「confidence 的含义」而不是「输出格式」。
- `confidence` 是模型自由发挥的浮点数，而 JEV 路径返回的是归一化概率（router.py:160-183 校验 `sum==1`）。**同一个 0.6/0.7/0.8 阈值（route_policy.py:106-110）作用在两种语义不同的数上**：JEV 的 0.6 是「36% 概率是别的」，LLM 的 0.6 通常只是「我没那么确定」。
- 更严重的是 `_finalize_route_intent`（router.py:197-200）在低置信时**把标签改写成 unknown**。看实测：

| id | 输入 | 期望 | 预测 | 置信 |
|---|---|---|---|---|
| RI-034 | 把订单状态改成已发货 | unsupported_action | unknown | 0.55 |
| RI-035 | 帮我把订单里的收货地址记录删除 | unsupported_action | unknown | 0.46 |

（`docs/reports/route_intent_live_eval_results.json`，36 例 94.4%，两例错误都是这个模式）

模型其实判对了，是 0.6 阈值把它降级成 unknown。因为 `unknown` 与 `unsupported_action` 的 `target_graph` 都是 `fallback`，**行为没有区别，但混淆矩阵失真、无法归因**——你看到的是「路由分类错误」，实际是「阈值降级」。

修法：阈值只在 policy 层决定「是否需要澄清 / 是否进 fallback」，不要回写 label。要保留可观测性就单独记 `confidence_gate: passed|demoted`。

### P0-4 ReadGraph 的工具返回的是成品话术，与提示词直接冲突

`kb_search`（kb.py:36-42）返回：

- 无结果 → `"未查询到相关知识，请换个说法或联系人工客服。"`
- 不可用 → `"知识库暂不可用，请稍后再试或联系人工客服。"`

而 `READ_SYSTEM_PROMPT` 要求：

- 第 2 条：「避免机械复述"未查询到"或生硬打发用户」
- 第 7 条：「工具返回错误时，不得将其转述为"系统故障/数据源不可用"」

工具吐出的正是模型被禁止说的话。模型要么违反提示词直接复述，要么二次改写——两种都不稳定。

修法：工具返回中性信号，话术归提示词。例如 `{"found": false}` → `"检索结果：空"`，或返回 `"（检索无结果）"` 这类不带客服语气的标记。`kb_search` 的 docstring 也要同步去掉「标注来源」的重复指令（提示词第 3 条已覆盖）。

---

## 3. P1 问题

### P1-1 Router 结构：11 个平行定义，缺决策顺序与对比样例

现状是「11 个标签 × 一段散文描述 + 一段全局规则」，没有判定顺序。冲突只能靠两条特例（`account_profile_update > order_mutation`、`shipment_query > order_query`）兜，其余靠模型自己权衡。

同时存在重复稀释：「缺少订单号不影响意图分类」在 criteria 里出现 4 次（order_query / account_profile_update / order_mutation / cancel / refund），instructions 里又出现 1 次。

`unsupported_action` 靠穷举例子（取消预约、清空历史、转移所有权、改用户名邮箱），覆盖不足——RI-034/035 的两个真实越界请求（改订单状态、删地址记录）都不在例子里。

建议改成三层判定树：

1. **问规则还是让我做事？** 问政策/流程/能不能 → `faq`（纯寒暄 → `smalltalk`）。例外：问某笔订单的状态/物流仍算查询类。
2. **做事 → 动作对象是谁？** 账户资料 / 订单集合 / 单笔订单信息 / 物流进度 / 改订单 / 取消 / 退款。
3. **对象不在能力内 → `unsupported_action`；对象和动作都解析不出 → `unknown`。**

再补 6-8 条**最小对比对**（contrastive pairs），专攻已观测到的混淆：

```
「取消订单的流程是什么？」 → faq
「订单 ORD-1 不要了，帮我取消」 → cancel_order_execute

「退款一般多久到账？」 → faq
「ORD-1 申请退款 99 元」 → refund_apply_execute

「订单 ORD-1 地址改成上海」 → account_profile_update   ← 有订单号也归账户
「订单 ORD-1 加个备注：放驿站」 → order_mutation

「把订单状态改成已发货」 → unsupported_action         ← 补进负例
「删除我的地址记录」 → unsupported_action
```

### P1-2 ReadGraph 提示词缺三条电商客服最关键的护栏

- **禁止承诺**：补偿金额、赔付、到账时效、上门时间。现有 7 条只禁止「编造信息」，没禁止「给出未经授权的承诺」。这是小家电售后最容易出事故的地方。
- **一次只问一个问题**：clarify 场景下模型容易一次抛 3 个问题，Widget 气泡体验差。
- **长度与格式**：无任何约束。建议「常规回答 ≤3 句 / 120 字；列参数用短横线；不输出 Markdown 标题」。
- **能力边界**：没有「不提供医疗/法律/投资建议」「不评价竞品」这类兜底。
- **`user_id` 条款（第 4 条）模型看不见**：`user_id` 在 state 里，不在 messages 里，模型无法验证。应改成行为约束：「只处理当前登录用户自己的订单，工具已自动限定范围；不要向用户索要他人的订单号或手机号」。

### P1-3 Fallback 不知道自己是哪类兜底

`unknown`（没听懂）、`unsupported_action`（能力不支持）、KB 无结果——三类原因，一套话术。而 `route_intent` 就在 state 里，可以注入一句场景提示。

另外第 3 条让模型「提示用户可以提出转接人工客服」，但 `check_handoff`（fallback.py:37-46）在 `fallback_count >= 4` 时**自动**转人工。结果：每一轮 fallback 都在劝转人工，第 5 轮系统自己转了——用户观感是「被推来推去」。

建议：`fallback_count < 2` 时只引导补充信息、不提转人工；≥2 才给人工出口。

### P1-4 品牌语气三处各写一套

`READ_SYSTEM_PROMPT`「语气亲切、耐心、简洁」/ `FALLBACK_SYSTEM_PROMPT`「像一位经验丰富的人工客服」/ `copy.py` 用「好的，…～」。建议抽一个共享片段（`BRAND_VOICE`）注入三个生成节点，确定性文案层也对照它写，避免人格分裂。

---

## 4. P2 工程化

| 问题 | 位置 | 建议 |
|---|---|---|
| 提示词无版本标识，改 prompt 无法归因到 eval 结果 | prompts.py 全文 | 加 `PROMPT_VERSION = "router@3"` 等常量，写进 `routing_backend` / 日志 |
| `_build_examples` 兜底生成假参数示例 `{"order_id": "order_id示例"}` | select.py:82 | 与「严禁编造」直接矛盾。无真实示例的工具**不生成示例**，或标成「缺参示例」 |
| select 每条请求构建两次 messages（第一次白算 token 预算） | select.py:284-305 | 先定 system 文本再算预算 |
| `SELECT_SYSTEM_TEMPLATE` 规则 2/3/4 重复讲「参数来源」 | prompts.py:134-150 | 合并为一条 + 一个正反例 |
| criteria 与 instructions 内容重叠 | prompts.py:11-85 | instructions 只放全局规则，criteria 只放边界 |

---

## 5. 改写稿

### 5.1 Router

```
你是澄元智能家电客服系统的意图路由器。只判断「这一轮用户想达成什么业务目标」，
不判断能否执行——权限、订单状态、工具可用性、审批都由后续确定性代码负责。

## 判定顺序（按序执行，命中即停）
第一步：这句话是在「问」还是在「让我做」？
  - 问政策、流程、规则、能不能、产品信息 → faq
  - 纯问候/感谢/告别/与业务无关 → smalltalk
  - 问某笔订单的状态、详情、物流进度 → 仍属查询类，进第二步
  - 例外：问「怎么取消/怎么退款/多久到账」是 faq，不是取消/退款操作

第二步：让我做 → 动作对象是谁？
  - 账户资料（收货地址、联系电话）→ account_profile_update
  - 订单集合（我有哪些订单、最近买了什么）→ my_orders
  - 单笔订单的信息/状态/详情 → order_query
  - 物流/配送/发货/签收/预计送达 → shipment_query
  - 修改订单内容（备注、发票、售后工单）→ order_mutation
  - 取消订单 → cancel_order_execute
  - 退款 → refund_apply_execute

第三步：兜底
  - 意图明确，但上面没有对应项（改订单状态、删地址记录、转移订单、改用户名邮箱、
    取消预约、合并订单…）→ unsupported_action
  - 连「要做什么」都解析不出（「帮我把那个东西处理一下」）→ unknown

## 边界规则
- 只做意图分类，不因缺订单号/金额/税号改判；参数由后续流程澄清。
- 当前消息出现新的明确目标时，以当前消息为准，不被 recent_context 的旧目标覆盖。
- recent_context 只用于解析指代和省略，不能用来判断「系统有没有这个能力」；
  能力边界只看上面的分类，不看历史 AI 回复里提过什么。
- 有订单号不等于 order_mutation：改地址/改电话仍归 account_profile_update。

## confidence 锚点
- 0.9-1.0：分类唯一合理，无第二解
- 0.7-0.85：主分类明确，存在弱竞争项
- 0.5-0.65：两个分类都说得通
- <0.5：只能靠猜，此时应选 unknown
```

配合代码：`_finalize_route_intent` 不再改写 label（见 P0-3）。

### 5.2 Select（统一版，真实路径启用）

保留 `bind_tools`，把 `tool_list` 与 `examples` 放回来，删掉「选最接近的工具」：

```
你是澄元智能家电客服的操作选择器。从「可用工具」中选出唯一最匹配的一个，
并抽取调用所需的参数，通过 tool_call 返回。

## 可用工具
{tool_list}

## 规则
1. 只能从「可用工具」中选择，tool 名必须逐字符一致，不得自创、不得使用中文描述。
2. args 只能包含该工具 schema 定义的字段；未提供的可选参数直接省略，
   不要填 "null"、"none"、"暂无"、0 或任何占位值。
3. 参数必须来自用户消息或对话中已明确出现的信息，严禁编造或推断。
   订单号、手机号、金额、税号必须能在上下文里逐字找到。
4. 必填参数缺失时仍然选该工具，只填已知参数；缺失由系统负责澄清，不要自己补齐。
5. 保留用户原始值，不要格式化或改写。

## 业务边界
- 售后工单（create_service_ticket）用于商品问题、退货但包装丢失、配件缺失等需要人工跟进的请求，不涉及退钱。
- 退款申请（refund_apply）只用于明确要求退回货款（说出退款金额、"退钱"、"退款"）。
- 用户同时说「售后」和「退货」时，核心诉求是售后处理，选 create_service_ticket。
- 修改收货地址/联系电话（update_address / update_phone）即使带订单号，也不选 order_mutation 类工具。

## 示例
{examples}
```

`tool_choice` 改 `"auto"`；无 tool_call → operation/tier clarify，不 reject。

### 5.3 ReadGraph

在现有 7 条上补 4 条，并改写第 4、7 条：

```
8. 禁止承诺：不得承诺赔付金额、补偿方案、退款到账时间、上门/维修时间；
   这些只能由人工或系统流程确认。可以说明「一般流程是…」，但要标明以实际处理为准。
9. 一次只问一个问题。需要用户补充信息时，先问最关键的那一个。
10. 长度：常规回答不超过 3 句 / 120 字；多项参数用短横线列出；不使用 Markdown 标题。
11. 不提供医疗、法律、投资建议；不评价、不比较竞品。
```

改写：

```
4. 只处理当前登录用户自己的订单。工具已自动限定数据范围，
   不要向用户索要他人的订单号、手机号，也不要声称可以查询他人订单。
7. 工具返回的是原始数据，不是最终话术。工具返回错误或空结果时，
   用你自己的客服语气重新组织，不要原样复述工具文本，也不要表述为「系统故障」「数据源不可用」。
```

配套：`kb_search` 返回中性信号（见 P0-4）。

### 5.4 Fallback

按 `route_intent` 注入一行场景，并让转人工节奏跟随 `fallback_count`：

```
场景：{scenario}
- unknown：没听懂用户要做什么
- unsupported_action：听懂了，但这项操作当前需要人工办理
- kb_miss：知识库没有查到相关内容

规则：
1. 先承接，再说明，最后给下一步；不要机械复述固定句式。
2. unknown → 请用户换个说法或补充关键信息（订单号、要办的事）。
3. unsupported_action → 说明这项操作需要人工协助，不要暗示「系统坏了」。
4. kb_miss → 如实说明没查到，请用户补充型号/订单号，或换个说法。
5. {handoff_hint}
   fallback_count < 2 → 「暂时不提转人工」
   fallback_count >= 2 → 「可以告知用户输入『转人工』由人工客服处理」
6. 不编造知识库中没有的信息，不假装已经处理。
```

---

## 6. 验收方式

| 改动 | 评测集 | 门槛 |
|---|---|---|
| Router 重构 | `tests/evals/router_benchmark/route_intent.jsonl`（42）+ `route_intent_multi_turn.jsonl`（9） | 准确率 ≥ 现有 94.4%（JEV 口径）；`unsupported_action` 召回 100%；多轮 ≥ 8/9 |
| Router 风险档 | `tests/evals/control/routing.jsonl`（75，capability/risk 口径） | `high_risk_recall` 从 0.50 提到 ≥ 0.80；`high_risk → mutation` 混淆从 6 降到 ≤ 1 |
| Select 统一 | `tests/evals/control/policy.jsonl`（10）+ 现有 select 单测 | 工具名零漂移；args 零编造（人工抽检 20 条） |
| Read | 现有 KB 场景 + 新增 10 条「诱导承诺」用例 | 零承诺输出 |
| Fallback | 现有 fallback 单测 + 5 条 unsupported_action 用例 | 三类场景话术可区分 |

注：75 例 `control/routing.jsonl` 是旧 capability/risk 口径，与 `route_intent` 标签非一一对应，只作风险档信号使用。改动前先跑一次基线存档，避免拿旧报告对比新代码。

## 7. 落地顺序

1. **P0-4 + 5.3**（工具返回中性化 + Read 护栏）：独立、无回归风险，先做。
2. **P0-3**（Router 阈值不再改写 label）：纯代码，1 行改动 + 评测基线重跑。
3. **P0-1/P0-2 + 5.2**（select 统一）：需要配套 `tool_choice` 与无 tool_call 分支，单独 PR。
4. **P1-1 + 5.1**（Router 结构重构）：收益最大、回归面也最大，放最后，用 42+9 例做门槛。
5. **P1-3 + 5.4**（Fallback 分支）：依赖 state 注入，可与 4 并行。
