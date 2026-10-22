# ChronoLens

MoonBit 实现的分布式日志时间约束诊断库，配套离线 CLI 与交互演示。

项目目标是通过明确的消息发送／接收关系，计算固定时钟偏移的可行范围，并给出时间约束冲突的证据。当前已完成目录骨架、[基础数据模型](model/README.md)、[JSONL 输入解析和校验](input/README.md)、[消息配对与关联诊断](correlate/README.md)、[差分约束构建](constraints/README.md)、[可行性与偏移区间](solver/README.md)、[JSON 和 Markdown 诊断报告](report/README.md)，以及 [正式文件分析 CLI](cmd/chronolens/README.md)。交互演示尚未实现。

## 目录结构

```text
chronolens/
├── moon.mod                 模块信息：Mitsuha11zz/chronolens
├── moon.pkg                 根包配置
├── chronolens.mbt            未来的公开入口
├── model/                   公共事件、约束与报告类型
├── input/                   JSONL 解析、校验与输入限制
├── correlate/               消息配对与关联质量诊断
├── constraints/             事件关系转换为差分约束
├── solver/                  可行性、偏移范围与负环见证
├── report/                  JSON／Markdown 报告与展示数据
├── cmd/chronolens/           native 文件分析 CLI
├── demo/                    后续交互演示
├── examples/two-services/    本机双进程 TCP 采集、输入转换与核心分析样例
├── examples/json-report/     JSON 报告导出例程及已生成的示例输出
├── fixtures/                后续输入与预期结果样例
├── docs/
│   ├── 开发方案.md           已确认选题的完整方案
│   ├── architecture.md      分包职责与依赖规划
│   └── progress.md          分阶段进度与确认记录
├── AGENTS.md                本项目开发约定
├── .gitattributes           文本行尾约定
├── .gitignore               构建产物忽略规则
└── LICENSE                  Apache-2.0
```

目录中的 `moon.pkg` 按功能实现加入具体依赖。`demo/` 目前只有范围说明；`fixtures/` 已包含四事件、混合关联、负环冲突及多分量输入样例。

## 开发与检查

从项目根目录运行：

```text
moon check --target all
moon run cmd/chronolens --target native -- fixtures/four-events.jsonl
moon info
moon fmt
```

CLI 从 JSONL 文件读取事件，可输出 JSON 或 Markdown 诊断报告；使用方式、限制参数和退出码见 [CLI 文档](cmd/chronolens/README.md)。

## 核心验证

2026-10-18：全项目 wasm、wasm-gc、js、native 各通过 111/111 测试，包括 384 个小图的独立 Floyd–Warshall 对照及 1,140 组任意精度算术边界对照。四事件区间、负环、单侧无界和独立分量样例已通过核心流水线测试，详情见 [核心验证记录](docs/core-validation.md)。该次验证未覆盖网络采集、诊断 CLI 或生产容量。

## 实际采集样例

[双进程样例](examples/two-services/README.md) 通过本机 TCP 实际采集发送／接收记录，转换成 JSONL，再由 MoonBit 核心分析。2026-10-20 已采集 3 次请求／响应、12 条事件；原始 B 偏移区间为 [-69,109] 微秒，B 时间戳减去 120000 微秒后，区间为 [119931,120109] 微秒。原始记录、注入副本和分析输出分别归档；这是同机双进程演示，不是多机器校时验证。

```text
python examples/two-services/run.py --analyze
python examples/two-services/run.py --replay examples/two-services/sample
```

生产容量、多机器时钟表现和交互演示仍待后续实现或验证。

## 诊断报告

report 包提供 from_input、from_analysis 和 from_failure，保留输入诊断、模型假设、关联覆盖、分量结果和冲突证据。可导出 chronolens.diagnostic.v1 JSON，也可生成同语义的 Markdown 阅读报告。Int64 在 JSON 中使用十进制字符串，区分有限边界、无界和计算失败。

详见 [报告契约](report/README.md) 和 [导出例程](examples/json-report/README.md)。已有 6 份 native 实际导出的 JSON 示例。

## 分阶段开发约定

先完成目录骨架，再逐个实现功能。每个功能完成后汇报变更、验证结果与待确认事项，停止并等待用户确认。推送需获得用户明确授权。

正式 CLI 已完成，等待用户确认。下一步拟实现交互演示，详见 [进度记录](docs/progress.md)。
