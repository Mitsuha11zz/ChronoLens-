# ChronoLens

MoonBit 实现的分布式日志时间约束诊断库，配套离线 CLI 与交互演示。

项目目标是通过明确的消息发送／接收关系，计算固定时钟偏移的可行范围，并给出时间约束冲突的证据。当前已完成目录骨架、[基础数据模型](model/README.md)、[JSONL 输入解析和校验](input/README.md)、[消息配对与关联诊断](correlate/README.md)及 [差分约束构建](constraints/README.md)，求解功能尚未实现。

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

目录中的 `moon.pkg` 是可识别的包骨架，具体依赖随功能实现加入。`demo/` 和 `fixtures/` 目前只有范围说明。

## 开发与检查

从项目根目录运行：

```text
moon check --target all
moon run cmd/chronolens --target native
moon info
moon fmt
```

CLI 当前仅说明项目处于骨架阶段，不执行日志诊断。

## 分阶段开发约定

先完成目录骨架，再逐个实现功能。每个功能完成后汇报变更、验证结果与待确认事项，停止并等待用户确认。推送需获得用户明确授权。

差分约束构建已完成，等待用户确认。下一步拟实现可行性判定与负环见证，详见 [进度记录](docs/progress.md)。
