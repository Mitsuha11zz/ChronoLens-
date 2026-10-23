# 包职责与依赖规划

model、input、correlate、constraints、solver 的核心分析以及 report 的 JSON／Markdown 导出均已实现。CLI 和本地交互演示也已接入核心流程。

| 包 | 职责 | 拟依赖 |
| --- | --- | --- |
| 根包 | 公开端到端入口与能力组合 | input、correlate、constraints、solver、report |
| model | 公共事件、约束、配置和结果类型 | 标准库 |
| input | JSONL 解析、字段校验、资源限制 | model |
| correlate | 按消息键配对，报告缺失与歧义；输入报告门控入口 | model、input |
| constraints | 将唯一消息对与显式偏移先验转为差分约束，保留未解决证据 | model、correlate |
| solver | 全图可行性、负环见证、参考坐标下的偏移区间与独立分量分析 | model、constraints |
| report | JSON／Markdown 诊断报告与证据展示 | model、input、correlate、constraints、solver |
| cmd/chronolens | 参数、文件 IO 与退出码 | 根包、report |
| demo | Python 标准库本机 HTTP 页面；调用 native CLI 并交互展示报告 | `cmd/chronolens` CLI、静态 HTML／CSS／JS |
| examples/two-services | Python 标准库采集本机双进程 TCP 记录，转换后由 native 样例入口调用核心分析 | input、correlate、constraints、solver、core/env |
| examples/otel-rpc | 将 OTLP JSON 的 RPC CLIENT/SERVER span 起始关系转换为 ChronoLens JSONL | Python 标准库、`cmd/chronolens` CLI |
| examples/json-report | native JSON 报告导出例程 | input、correlate、constraints、solver、report、core/env |

`model/` 是公开包，用户需要构造、匹配或调用方法的公共类型由该包持有。后续增加内部扫描器等辅助包时，不将公共具体类型迁入 `internal/`。

输入、IO 和展示与求解算法分开；算法接收结构化数据并返回结构化结果。所有时间值采用有溢出检查的 64 位整数运算。

交互演示只负责本地输入、CLI 调用和报告呈现，不在浏览器端复制求解逻辑。服务绑定 `127.0.0.1`，浏览器展示使用已有 JSON 报告；代表时间线基于同一组可行偏移，分量坐标相互独立且不代表 UTC。

OpenTelemetry 适配器是独立的转换示例，不扩大核心输入模型。它只使用同一 trace 中直接以 CLIENT span 为父的 SERVER span，并将两边起始时间作为因果事件；一般 Span 父子关系不自动转换为消息约束。

固定定义：`模型时间 = 原始时间 + 时钟偏移`。约束 `o_i - o_j <= c` 转换为边 `j -> i`、权重 `c`。区间与冲突结论均受输入关联和固定偏移假设约束。
