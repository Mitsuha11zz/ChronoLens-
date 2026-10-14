# correlate

职责：按 trace_id、message_id、attempt 配对发送／接收事件，报告缺失和歧义。

## 入口

调用方导入 `Mitsuha11zz/chronolens/correlate`，使用别名 `correlate`。

- `correlate(events, max_events?)`：对模型事件集合进行配对。重复事件 ID 会拒绝整份集合，不静默去重。
- `correlate_input(report, max_events?)`：对已完成且无错误的 InputReport 进行配对。非法输入或资源截断的预览被拒绝。

两个入口均可能抛出 CorrelationError。默认事件上限为 10000，可配置范围为 1 至 1000000；超过数量上限会报告 limit 与 count。

## 配对规则

分组键完整使用 `(trace_id, message_id, attempt)`，不会拼接字符串来代替消息键。不同 trace、消息 ID 或重试尝试互相隔离。

只有同组恰好一条 Send 和一条 Receive 时才生成 MessagePair。事件原来的时间戳、时钟域和来源位置全部保留。

配对不使用时间戳先后、时钟是否相同或“离得最近”来选择候选。接收早于发送仍能形成唯一配对；时间矛盾由后续约束功能检查。

| 发送数 | 接收数 | 结果 |
| ---: | ---: | --- |
| 1 | 1 | 唯一配对 |
| 0 | 1 | MissingSend |
| 1 | 0 | MissingReceive |
| 多于 1 | 任意数量 | Ambiguous；若接收数为 0，同时报告 MissingReceive |
| 任意数量 | 多于 1 | Ambiguous；若发送数为 0，同时报告 MissingSend |

未解决的组保留全部发送与接收证据，不选择某一候选，也不补造缺失事件。

## 结果与统计

CorrelationReport 含只读 pairs、只读 unresolved 和 stats。MessagePair 保存 key、send_event、receive_event；UnresolvedGroup 保存 key、全部 send_events／receive_events 以及只读 issues。

统计字段为 total_events、group_count、paired_groups、unresolved_groups、missing_groups 和 ambiguous_groups。缺失与歧义可能同时发生，所以 missing_groups 与 ambiguous_groups 不一定互斥。

满足以下守恒关系：

```text
group_count = paired_groups + unresolved_groups
total_events = 2 × paired_groups + 未解决组中全部发送／接收事件数
```

`fully_paired()` 表示没有未解决组，不代表时间约束可行。空的类型化事件集合会返回 true，但 total_events 和 group_count 均为 0；不能将其解释为具有完整日志证据。JSONL 空输入仍由输入层判为无效。

结果按 trace_id、message_id、attempt 升序排列，同组证据按 event_id 升序排列，字符串使用 MoonBit 的比较规则。相同事件集合的输入排列变化不会改变结果，也不会修改调用方数组。

## 集成示例

以下代码需放在允许传播输入与配对错误的函数或测试中，text 为符合输入层契约的 JSONL：

```mbt
let parsed = @input.parse_jsonl(text, source_path="events.jsonl")
let report = @correlate.correlate_input(parsed)
println(report.stats.paired_groups)
```

当输入有效但有缺失或歧义时，返回诊断报告；只有非法输入、重复事件 ID 或资源配置问题才抛出本阶段错误。

## 验证

17 项黑盒测试覆盖唯一配对、trace／消息／重试隔离、缺失与歧义并存、保留全部事件、确定性排序、分隔符碰撞、重复 ID、事件上限、空集合、极端时间戳及 JSONL 集成。

2026-10-14：全项目 wasm、wasm-gc、js、native 各通过 60/60。该结果验证消息关联行为，时间约束构建与求解尚未实现。
