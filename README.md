# ChronoLens

MoonBit 实现的分布式日志时间约束诊断库，配套离线 CLI 与本地交互演示。

项目目标是通过明确的消息发送／接收关系，计算固定时钟偏移的可行范围，并给出时间约束冲突的证据。当前已完成目录骨架、[基础数据模型](model/README.md)、[JSONL 输入解析和校验](input/README.md)、[消息配对与关联诊断](correlate/README.md)、[差分约束构建](constraints/README.md)、[可行性与偏移区间](solver/README.md)、[JSON 和 Markdown 诊断报告](report/README.md)、[正式文件分析 CLI](cmd/chronolens/README.md)以及[本地交互演示](demo/README.md)。

## 目录结构

```text
chronolens/
├── moon.mod                 模块信息：Mitsuha11zz/chronolens
├── moon.pkg                 根包配置
├── chronolens.mbt            根包公开入口
├── analysis.mbt              JSONL 端到端分析编排
├── model/                   公共事件、约束与报告类型
├── input/                   JSONL 解析、校验与输入限制
├── correlate/               消息配对与关联质量诊断
├── constraints/             事件关系转换为差分约束
├── solver/                  可行性、偏移范围与负环见证
├── report/                  JSON／Markdown 报告与展示数据
├── cmd/chronolens/           native 文件分析 CLI
├── demo/                    本机浏览器工作台与 CLI 请求桥接
├── benchmarks/              可复现的 native CLI 容量基准
├── integration_tests/       OTLP 与本地演示的端到端回归
├── examples/two-services/    本机双进程 TCP 采集、输入转换与核心分析样例
├── examples/otel-rpc/        OTLP JSON RPC Span 转 ChronoLens JSONL
├── examples/json-report/     JSON 报告导出例程及已生成的示例输出
├── fixtures/                后续输入与预期结果样例
├── docs/
│   ├── architecture.md      分包职责与依赖规划
│   └── progress.md          分阶段进度与确认记录
├── AGENTS.md                本项目开发约定
├── .gitattributes           文本行尾约定
├── .gitignore               构建产物忽略规则
└── LICENSE                  Apache-2.0
```

目录中的 `moon.pkg` 按功能实现加入具体依赖。`demo/` 使用 Python 标准库提供本地页面并转发到 MoonBit native CLI；`fixtures/` 包含四事件、混合关联、负环冲突及多分量输入样例。

## 开发与检查

从项目根目录运行：

```text
moon check --target all
moon run cmd/chronolens --target native -- fixtures/four-events.jsonl
moon info
moon fmt
```

CLI 从 JSONL 文件读取事件，并通过根包公开 API 执行分析，可输出 JSON 或 Markdown 诊断报告；使用方式、限制参数和退出码见 [CLI 文档](cmd/chronolens/README.md)。启动浏览器演示：

```text
python demo/server.py
```

服务只监听 `127.0.0.1:8765`，启动时构建 native CLI。演示说明和模型边界见 [demo 文档](demo/README.md)。

## MoonBit 库 API

其他 MoonBit 项目可以直接调用根包完成 JSONL 解析、关联、约束分析和诊断报告生成：

```mbt
let diagnostic = @chronolens.analyze_jsonl(jsonl)
let json = diagnostic.stringify(pretty=true)
```

`analyze_jsonl` 默认使用零容差和包内资源限制，也可传入 `AnalysisOptions` 指定输入限制、消息关系容差、参考时钟和求解限制。已知的时钟相对偏移范围可通过 `priors` 参数传入：

```mbt
let diagnostic = @chronolens.analyze_jsonl(jsonl, priors=[prior])
```

`prior` 由 `@constraints.OffsetPrior::new(...)` 创建；该构造器会校验标识和边界范围，错误时抛出 `ConstraintBuildError`。先验标签必须唯一；先验可引入新时钟域，但不会自动锚定到 UTC。非法 JSONL 与分析阶段失败会以结构化诊断报告返回；报告本身与 CLI 使用相同的数据契约。最终报告与输入无法匹配时会抛出 `ReportError`。

如果调用方已经构造好 `ArrayView[model.Event]`，可跳过 JSONL 编码和解析：

```mbt
let diagnostic = @chronolens.analyze_events(events)
```

这个入口沿用相同的关联、求解选项、`priors` 参数和报告格式；由于没有运行 JSONL 解析，报告中的 `input` 字段为 `null`。事件数上限取配置值和关联包硬上限中的较小值。

## OpenTelemetry RPC 数据

`examples/otel-rpc/` 提供一个标准库转换器，将 OTLP JSON trace 导出的 RPC CLIENT/SERVER Span 起始关系转换为 JSONL，再交由同一 MoonBit CLI 分析。转换语义、时钟域选择和限制见 [适配器文档](examples/otel-rpc/README.md)。

## 核心验证

2026-10-18：全项目 wasm、wasm-gc、js、native 各通过 111/111 测试，包括 384 个小图的独立 Floyd–Warshall 对照及 1,140 组任意精度算术边界对照。四事件区间、负环、单侧无界和独立分量样例已通过核心流水线测试，详情见 [核心验证记录](docs/core-validation.md)。该次验证未覆盖网络采集、诊断 CLI 或生产容量。

## 实际采集样例

[双进程样例](examples/two-services/README.md) 通过本机 TCP 实际采集发送／接收记录，转换成 JSONL，再由 MoonBit 核心分析。2026-10-20 已采集 3 次请求／响应、12 条事件；原始 B 偏移区间为 [-69,109] 微秒，B 时间戳减去 120000 微秒后，区间为 [119931,120109] 微秒。原始记录、注入副本和分析输出分别归档；这是同机双进程演示，不是多机器校时验证。

```text
python examples/two-services/run.py --analyze
python examples/two-services/run.py --replay examples/two-services/sample
```

生产容量和多机器时钟表现仍待验证；本地交互演示、限定范围的 OpenTelemetry RPC 适配器和容量基准工具已完成。

## 容量基准

使用 [`benchmarks/capacity.py`](benchmarks/capacity.py) 生成确定规模的成对消息日志，并调用正式 native CLI 测量端到端耗时；参数说明见[基准文档](benchmarks/README.md)：

```text
python benchmarks/capacity.py
python benchmarks/capacity.py --messages 100,1000 --repeats 5 --warmups 1
```

工具将 JSON 结果写到标准输出；默认测量 100、1,000 和 5,000 条消息，每档运行 3 次并报告中位数。耗时包含 CLI 进程启动、输入读取、分析和报告写入，不包含构建和数据生成。基准使用两个时钟域和一个连通分量，结果用于比较本地版本，不代表多时钟拓扑、峰值内存或生产环境容量保证。

## 集成回归

运行标准库端到端检查，覆盖 OTLP 样例转换到 CLI，以及本地演示 HTTP 样例接口到 CLI 的分析链路：

```text
python -m unittest discover -s integration_tests -v
```

测试会先构建 native CLI，演示服务使用随机本机端口，测试数据和报告在系统临时目录中创建并自动清理。

GitHub Actions 工作流 `CI` 会在每次 push、pull request 或手动触发时运行全后端检查与测试、native CLI 构建、Python／JavaScript 语法检查和上述端到端回归。

## 诊断报告

report 包提供 from_input、from_analysis 和 from_failure，保留输入诊断、模型假设、关联覆盖、分量结果和冲突证据。可导出 chronolens.diagnostic.v1 JSON，也可生成同语义的 Markdown 阅读报告。Int64 在 JSON 中使用十进制字符串，区分有限边界、无界和计算失败。

详见 [报告契约](report/README.md) 和 [导出例程](examples/json-report/README.md)。已有 6 份 native 实际导出的 JSON 示例。

## 分阶段开发约定

先完成目录骨架，再逐个实现功能。每个功能完成后汇报变更、验证结果与待确认事项，停止并等待用户确认。推送需获得用户明确授权。

正式 CLI、本地交互演示、OpenTelemetry RPC 适配器与容量基准工具已完成；当前功能等待用户确认后再进入下一阶段，详见 [进度记录](docs/progress.md)。
