# constraints

职责：将明确的事件关联与用户先验转换为差分约束，并保存证据来源。

## 入口与约定

`build(correlation, relation_tolerance_us?=0L, priors?=[], max_constraints?=20000)` 返回只读 `ConstraintSet`，失败抛出 `ConstraintBuildError`，不会返回部分构建结果。约束数量上限可配置为 1 至 2,000,000。

固定模型为 `模型时间 = 观测时间 + 时钟偏移`。一条发送时间为 s、接收时间为 r 的唯一消息对形成：

```text
o_send - o_receive <= r - s + tolerance
```

容差必须非负，单位为微秒；它放宽消息因果不等式，是显式模型假设。边方向为 receive_clock → send_clock。`BuiltConstraint` 同时保存基础约束、完整消息对及使用的容差，来源行号随原始事件保留。

`OffsetPrior::new(clock_id~, reference_clock~, label~, lower_us?, upper_us?)` 表示：

```text
lower <= o_clock - o_reference <= upper
```

至少给出一个边界，双边界须满足 lower ≤ upper。下界转换为 `o_reference - o_clock <= -lower`，上界保持正向；每条边保存原先验及边界种类。同一次构建中 label 必须唯一。先验可以引入新的时钟域，不会自动锚定到 UTC。

## 边界与证据

- 唯一消息对产生约束；缺失或歧义组不产生约束，完整关联报告仍在结果中，涉及的时钟也不会丢失。
- 时钟按名称排序，消息按关联报告的消息键顺序排列，先验按标签排序；同一先验先下界后上界。
- 所有约束运算检查 Int64 溢出；消息表达式会重排运算，避免最终值可表示时因中间溢出误拒绝。无法表示的最终值使整次构建失败，错误携带消息 ID 或先验标签。
- 下界为 Int64 最小值时，其相反数无法表示，构建明确报错；不会静默删除边界。
- 允许负权自环和互相冲突的先验；本包仅构建图，不判断可行性或检测负环。

`fixtures/four-events.jsonl` 在零容差、无先验时应生成 `o_A-o_B <= -100000` 和 `o_B-o_A <= 160000`。这只是约束推导，尚未执行偏移区间求解。
