# OpenTelemetry RPC trace 适配器

此示例把 OTLP JSON trace 导出转换为 ChronoLens JSONL，再由正式 CLI 或本地交互演示分析。转换脚本使用 Python 标准库；时钟约束仍由 ChronoLens MoonBit 核心计算。

## 使用

```text
python examples/otel-rpc/convert.py exported-traces.json --output events.jsonl
moon run cmd/chronolens -- events.jsonl
```

也可以启动 `python demo/server.py`，然后在浏览器工作台中载入生成的 `events.jsonl`。已有输出文件默认拒绝覆盖；确认替换时添加 `--force`。默认输入和生成文件各限制为 8 MiB，RPC span 事件最多 10,000 条，时钟域最多 64 个。

转换器读取标准 `ExportTraceServiceRequest` JSON 形状中的 `resourceSpans`、`scopeSpans` 和 `spans`。OTLP JSON 使用 lowerCamelCase 字段，Trace ID 和 Span ID 使用十六进制字符串，`kind` 使用数字枚举；64 位时间戳接受十进制字符串或精确 JSON 整数。未知字段忽略，重复 JSON 键拒绝。时间戳从纳秒向下取整为微秒。

## 转换规则和假设

- 只转换 `kind=3`（CLIENT）和 `kind=2`（SERVER）；其他 SpanKind 会统计后忽略。
- 一条 CLIENT span 产生一个 `send` 事件，时间取 `startTimeUnixNano`；一条 SERVER span 产生一个 `receive` 事件，时间也取其 `startTimeUnixNano`。
- 仅当 trace ID 相同且 SERVER 的 `parentSpanId` 指向该 CLIENT 的 `spanId` 时，二者才共享请求 message ID。这个约束表达“客户端调用已发起，服务端随后开始处理”的因果先后，不把 span 区间解释为网络报文时间。
- 同一 CLIENT 出现多个直接 SERVER 子 Span 时，全部保留，让 ChronoLens 报告该消息键存在歧义。客户端或服务端 Span 缺失时保留单边事件，不补造另一端。
- 默认使用 `service.instance.id` 作为时钟标识，并组合 `service.name` 和可选 `service.namespace`，区分不同服务的实例。缺少 `service.name` 或 `service.instance.id` 时会报错。
- 如果同一物理时钟包含多个服务，且导出中提供 `host.name`，可传 `--clock-attribute host.name`，把同一主机上的 Span 归入一个时钟域。传入其它属性名时，属性值必须是非空字符串，并且应确实唯一标识目标时钟域。
- 事件 ID 和 message ID 包含 OTLP Trace/Span 标识。转换后的 JSONL 行号由 ChronoLens 输入解析器记录；原 OTLP 是嵌套 JSON，不伪造原文件行号。

RPC 语义依据 OpenTelemetry 的 [RPC span conventions](https://opentelemetry.io/docs/specs/semconv/rpc/rpc-spans/)。OTLP JSON 字段和编码依据 [OTLP specification](https://opentelemetry.io/docs/specs/otlp/)。`service.name` 与 `service.instance.id` 的标识含义见 [service resource conventions](https://opentelemetry.io/docs/specs/semconv/resource/service/)。

## 内置样例

`sample-traces.json` 包含一条可关联的 RPC、一条只有客户端 Span 的调用，以及一条找不到客户端父 Span 的服务端记录：

```text
python examples/otel-rpc/convert.py examples/otel-rpc/sample-traces.json --output _build/otel-events.jsonl
moon run cmd/chronolens -- _build/otel-events.jsonl --format markdown
```

这个适配器只覆盖 OTLP JSON 中的 RPC CLIENT/SERVER 起始关系。它不把 INTERNAL、PRODUCER、CONSUMER Span 或普通父子 Span 自动转换成消息约束；不适用于从不完整采样的 trace 推断完整因果关系，也不估计绝对 UTC 偏差。
