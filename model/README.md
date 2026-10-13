# model

职责：公共事件、消息键、证据来源与基础差分约束。

## 已实现接口

| 类型 | 契约 |
| --- | --- |
| `EventKind` | `Send`、`Receive` 两种消息事件 |
| `MessageKey` | `(trace_id, message_id, attempt)`，可作为 Map 键，重试和不同 trace 相互隔离 |
| `SourceLocation` | 来源路径与从 1 开始的行号 |
| `Event` | 事件 ID、时钟 ID、消息键、种类、Int64 微秒时间戳及可选来源 |
| `ConstraintOrigin` | 消息事件引用，或用户先验的标签 |
| `DifferenceConstraint` | `offset(left_clock) - offset(right_clock) <= upper_bound_us` |
| `ModelError` | 空白标识、负重试索引、非法来源行号 |

记录类型通过 `new` 构造，并提供同名字段访问方法。构造器拒绝空白标识，但保留合法标识的原始字符，不会自动去掉首尾空格或改写大小写。消息事件引用是否存在、事件 ID 是否重复等集合级校验由后续输入与关联功能负责。

时间戳和约束权重均为完整范围的有符号 `Int64` 微秒数；模型允许负值。当前仅保存数值，后续计算需要独立检查算术溢出。

约束的图边方向固定为 `right_clock -> left_clock`，对应 `edge_from()` 与 `edge_to()`。同一时钟的负上界约束也允许构造，由后续求解器判断冲突。

## 调用示例

调用方需在包配置中导入 `Mitsuha11zz/chronolens/model` 并使用别名 `model`。

```mbt
let key = @model.MessageKey::new(
  trace_id="t1", message_id="request-1", attempt=0,
)
let event = @model.Event::new(
  event_id="a1", clock_id="A", key~, kind=@model.Send,
  timestamp_us=1000000L,
)
let constraint = @model.DifferenceConstraint::new(
  left_clock="A", right_clock="B", upper_bound_us=-100000L,
  origin=@model.Message(send_event_id="a1", receive_event_id="b1"),
)
```

示例需放在允许传播 `ModelError` 的函数或测试中；生产调用方也可捕获该错误。

## 验证

`model_test.mbt` 包含 9 项黑盒契约测试，覆盖标识校验、重试隔离、Map 键、完整时间戳范围、可选来源、证据引用和约束边方向。

运行 `moon test model --target all`。本阶段已通过 wasm、wasm-gc、js、native 四个后端，各 9/9。
