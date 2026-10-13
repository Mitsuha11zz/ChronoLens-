# 分阶段进度

## 2026-10-13：阶段 0，目录骨架

- 创建独立 MoonBit 模块与 Git 仓库。
- 建立 model、input、correlate、constraints、solver、report 包目录。
- 建立 CLI 占位入口以及 demo、fixtures、docs 目录。
- 配置仓库本地 Git 用户：Mitsuha11zz，936163794@qq.com。
- 业务功能尚未实现。本阶段完成后等待用户确认。

骨架验证已通过：`moon check --target all`、`moon info`、`moon fmt`、`moon run cmd/chronolens --target native`。CLI 仅输出骨架状态；本阶段没有业务测试或算法验证。

Git 分支为 `main`，未配置远程，未创建提交，未推送。

## 2026-10-13：阶段 1，基础数据模型（已完成，待用户确认）

范围：事件身份、时钟域、消息键、发送／接收种类、微秒时间戳，以及差分约束的基础表示。明确公共类型的归属和字段契约。

已实现 `EventKind`、`MessageKey`、`SourceLocation`、`Event`、`ConstraintOrigin`、`DifferenceConstraint` 与 `ModelError`。记录构造器校验单条数据，保留标识原文；时间戳与约束上界使用 Int64 微秒。

约束固定表达 `offset(left_clock) - offset(right_clock) <= upper_bound_us`，图边由右侧时钟指向左侧时钟。尚未从日志自动构建约束或执行求解。

验证结果：`moon check --target all` 无警告、无错误；`moon test --target all` 在 wasm、wasm-gc、js、native 上各通过 9/9 黑盒测试；`moon info` 和 `moon fmt` 已执行，公开接口已生成。

测试覆盖重试与 trace 隔离、Map 键行为、空白标识、标识原文保留、Int64 全范围、来源行号、可选来源、约束边方向、自环与证据字段校验。

未创建 Git 提交，未推送。完成本阶段后停止等待用户确认。

2026-10-13：已将用户提供的 `https://github.com/Mitsuha11zz/ChronoLens-.git` 配置为本地 `origin`，并更新模块仓库地址。仅配置地址，未确认远程内容或访问权限，未提交或推送。当前仍停在基础数据模型完成阶段。

2026-10-13：用户明确授权首次提交并推送。远程分支查询成功且当前没有分支引用；本次提交范围为目录骨架、基础数据模型、测试与文档。提交与推送结果以 Git 记录为准，下一功能仍需用户另行确认开始。

## 下一功能：JSONL 输入解析与校验（待用户确认开始）

范围：解析方案约定的字段，将时间戳十进制字符串转换为 Int64，验证必填字段、重复事件 ID、非法行和输入限制，输出结构化输入诊断。消息配对和约束求解安排在后续功能中。

## 后续功能顺序

1. 基础数据模型。
2. JSONL 输入解析与校验。
3. 消息配对与关联诊断。
4. 差分约束构建。
5. 可行性与负环见证。
6. 偏移区间与分量分析。
7. 报告与 CLI。
8. 交互演示与交付整理。

每次只推进一个确认过的功能，完成后停止等待确认。没有推送授权时不执行 `git push`。
