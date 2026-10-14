# 分阶段进度

## 2026-10-13：阶段 0，目录骨架

- 创建独立 MoonBit 模块与 Git 仓库。
- 建立 model、input、correlate、constraints、solver、report 包目录。
- 建立 CLI 占位入口以及 demo、fixtures、docs 目录。
- 配置仓库本地 Git 用户：Mitsuha11zz，936163794@qq.com。
- 业务功能尚未实现。本阶段完成后等待用户确认。

骨架验证已通过：`moon check --target all`、`moon info`、`moon fmt`、`moon run cmd/chronolens --target native`。CLI 仅输出骨架状态；本阶段没有业务测试或算法验证。

Git 分支为 `main`，未配置远程，未创建提交，未推送。

## 2026-10-13：阶段 1，基础数据模型（已确认并推送）

范围：事件身份、时钟域、消息键、发送／接收种类、微秒时间戳，以及差分约束的基础表示。明确公共类型的归属和字段契约。

已实现 `EventKind`、`MessageKey`、`SourceLocation`、`Event`、`ConstraintOrigin`、`DifferenceConstraint` 与 `ModelError`。记录构造器校验单条数据，保留标识原文；时间戳与约束上界使用 Int64 微秒。

约束固定表达 `offset(left_clock) - offset(right_clock) <= upper_bound_us`，图边由右侧时钟指向左侧时钟。尚未从日志自动构建约束或执行求解。

验证结果：`moon check --target all` 无警告、无错误；`moon test --target all` 在 wasm、wasm-gc、js、native 上各通过 9/9 黑盒测试；`moon info` 和 `moon fmt` 已执行，公开接口已生成。

测试覆盖重试与 trace 隔离、Map 键行为、空白标识、标识原文保留、Int64 全范围、来源行号、可选来源、约束边方向、自环与证据字段校验。

未创建 Git 提交，未推送。完成本阶段后停止等待用户确认。

2026-10-13：已将用户提供的 `https://github.com/Mitsuha11zz/ChronoLens-.git` 配置为本地 `origin`，并更新模块仓库地址。仅配置地址，未确认远程内容或访问权限，未提交或推送。当前仍停在基础数据模型完成阶段。

2026-10-13：用户明确授权首次提交并推送。远程分支查询成功且当前没有分支引用；本次提交范围为目录骨架、基础数据模型、测试与文档。提交与推送结果以 Git 记录为准，下一功能仍需用户另行确认开始。

首次推送已核对远程与本地提交一致：`cb9b45923a9ff72ea8972002f79b074115d70723`。

## 2026-10-14：阶段 2，JSONL 输入解析与校验（已完成并获用户确认）

范围：解析方案约定的字段，将时间戳十进制字符串转换为 Int64，验证必填字段、重复事件 ID、非法行和输入限制，输出结构化输入诊断。消息配对和约束求解安排在后续功能中。

已实现 parse_jsonl、InputLimits、InputReport、InputIssue、IssueKind、InputStatus 和 InputConfigError。字段、时间戳、事件 ID、来源、未知／重复 JSON 字段及 Unicode 均有明确校验，错误记录实际输入行号。

报告区分扫描完成与资源截断。事件预览和诊断为只读集合；只有整份输入通过验证，validated_events() 才返回独立事件数组。首版提供七项输入限制，并限制可配置总字节与 JSON 深度的硬上限。

2026-10-14 恢复中断工作后，边界测试发现 JSON 浮点舍入会误接受接近整数的小数。现已在记录扫描中保留 attempt 和 source.line 的原始数字文本，使用十进制系数与指数进行精确校验，覆盖舍入、下溢、范围边界和转义字段名。

最终验证：34 项新增输入契约测试，全项目四后端各通过 43/43；moon check --target all 无警告、无错误；公开接口已生成，代码已格式化。

2026-10-14：用户明确授权本阶段提交和推送，范围为 JSONL 输入实现、测试、样例、公开接口和阶段文档；提交与推送结果以 Git 记录为准。CLI 仍为占位入口，下一功能等待用户另行确认开始。

## 下一功能：消息配对与关联诊断（待用户确认开始）

范围：根据 (trace_id, message_id, attempt) 对已验证事件进行配对，输出唯一发送／接收对、缺失记录和歧义诊断。约束构建和求解留到后续功能。

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
