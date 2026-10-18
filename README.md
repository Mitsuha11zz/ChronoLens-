# ChronoLens

MoonBit 实现的分布式日志时间约束诊断库，配套离线 CLI 与交互演示。

项目目标是通过明确的消息发送／接收关系，计算固定时钟偏移的可行范围，并给出时间约束冲突的证据。当前已完成目录骨架、[基础数据模型](model/README.md)、[JSONL 输入解析和校验](input/README.md)、[消息配对与关联诊断](correlate/README.md)、[差分约束构建](constraints/README.md)，以及 [可行性、负环见证、偏移区间和分量分析](solver/README.md)。报告导出、诊断 CLI 和交互演示尚未实现。

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
├── cmd/chronolens/           CLI 占位入口
├── demo/                    后续交互演示
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
moon run cmd/chronolens --target native
moon info
moon fmt
```

CLI 当前仅说明项目处于骨架阶段，不执行日志诊断。

## 核心验证

2026-10-18：全项目 wasm、wasm-gc、js、native 各通过 111/111 测试，包括 384 个小图的独立 Floyd–Warshall 对照及 1,140 组任意精度算术边界对照。四事件区间、负环、单侧无界和独立分量样例已通过核心流水线测试，详情见 [核心验证记录](docs/core-validation.md)。当前仍未验证真实双服务采集、诊断 CLI 或生产容量。

## 分阶段开发约定

先完成目录骨架，再逐个实现功能。每个功能完成后汇报变更、验证结果与待确认事项，停止并等待用户确认。推送需获得用户明确授权。

偏移区间、分量分析与核心验证已完成，等待用户确认。下一步拟补充真实双服务采集与格式转换样例，再继续报告与 CLI，详见 [进度记录](docs/progress.md)。
