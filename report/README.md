# JSON 诊断报告

提供 schema_version 为 chronolens.diagnostic.v1 的核心诊断导出。只负责把已有输入诊断或求解结果转换为 JSON，不进行文件 IO、重新求解或 Markdown 渲染。

## 入口

~~~mbt
let diagnostic = @report.from_analysis(analysis, input=parsed)
let value = diagnostic.to_json()
let text = diagnostic.stringify(pretty=true)
~~~

上面的代码放在允许传播 ReportError 的函数中，analysis 为 solver.AnalysisReport，parsed 为 input.InputReport。

| 入口 | 用途 |
| --- | --- |
| from_input(input) | 输出解析诊断和已接受事件，不声称执行过分析 |
| from_analysis(analysis, input?) | 输出完整分量与证据报告，可附解析质量信息 |
| from_failure(failure, input?) | 输出实际失败阶段与错误，保留已有解析信息 |
| DiagnosticReport.to_json() | 返回独立的 Json 值，修改它不改变报告源数据 |
| DiagnosticReport.stringify(pretty=false) | 按确定的对象键顺序输出文本；pretty=true 使用两空格缩进 |

若给 from_analysis 附带 input，输入必须整份有效，事件集合及每个事件的字段、时间戳、来源都须与分析源完全相同；否则抛出 InvalidInputReport 或 MismatchedInputEvents。未附带时 input 为 null，不替调用方编造解析验证结论。

PipelineFailure 区分 InputConfiguration、Correlation、ConstraintBuild、Solver，分别接收对应包的实际类型化错误。调用者负责传入实际发生的阶段与错误；报告层不重跑或推断它们。

## v1 字段

正式字段结构见 [diagnostic-v1.schema.json](diagnostic-v1.schema.json)。该文件采用 JSON Schema draft 2020-12，显式版本化，并拒绝根对象和主要数据对象的未知字段。

| 字段 | 内容 |
| --- | --- |
| schema_version、producer | 报告结构版本与库模块／版本 |
| status、has_conflicts | 分析状态及三值冲突信息 |
| input | 解析是否有效、扫描是否完整、限制原因、实际输入行诊断；可能为 null |
| coverage | 成功配对、缺失、歧义及事件覆盖统计；缺失与歧义计数可能重叠 |
| model | 固定偏移定义、容差、实际偏移先验及参考坐标范围 |
| events | 按 event_id 的 UTF-16 字典序排列的原始事件，含来源位置 |
| messages、unresolved_groups | 唯一配对及全部未解决组，使用事件 ID 回查 |
| constraints | 原始约束顺序、边方向、上界、来源与消息／先验证据 |
| components | 独立分量的参考时钟、状态、偏移区间、代表解、负环或错误 |
| summary | 分量计数、成功分量的无界时钟计数及实际运算统计 |
| failure | 未生成分析报告时，保存的失败阶段与 code／details；否则为 null |
| assumptions | 固定偏移、消息关联、参考坐标、不确定性等模型约定 |

当前源报告没有保存实际使用的输入／构建／求解上限，所以 model.resource_limits 为 null，并标记 not_available_in_source_reports。不会用默认值冒充当次实际配置。每个分量使用的实际 reference_clock、实际容差、实际先验及已消耗 edge_visits 均可导出。

## 状态语义

| status | 含义 |
| --- | --- |
| not_analyzed | 输入有效，但只导出了输入信息 |
| input_invalid | 输入非法，没有进行约束分析 |
| input_limited | 输入扫描被资源限制截断，接受事件仅为预览 |
| pipeline_failed | 已有阶段错误，尚未获得可导出的完整分析报告 |
| no_constraints | 已执行分量分析，但没有构建任何约束 |
| feasible | 全部已构建分量完成且无冲突，至少有一条约束 |
| infeasible | 分量均完成，至少一个分量存在负环 |
| analysis_incomplete | 至少一个分量计算失败，其他结果仍逐项保留 |

has_conflicts=true 表示至少发现一个冲突；全部分量完成且无冲突时为 false。没有执行分析，或部分分量失败且尚未发现冲突时为 null。分析未完成时仍可能因为其他分量已找到负环而为 true。

可行性只针对已构建约束。即使 status=feasible，coverage.pairing_status 仍可能是 has_unresolved_groups；log_completeness 始终是 unknown，不把成功配对等同于日志完整。

## 时间和无界编码

所有 Int64 均为精确十进制字符串：ts_us、offset_us、value_us、upper_bound_us、relation_tolerance_us、先验边界、环权总和和 edge_visits 等。事件数、数组索引、attempt 和来源行号属于 Int32，保持 JSON 整数。

~~~json
{
  "clock_id": "D",
  "lower": {"kind": "finite", "value_us": "-50"},
  "upper": {"kind": "unbounded"}
}
~~~

lower 的 unbounded 表示下侧无界，upper 的 unbounded 表示上侧无界。计算失败时 intervals 为 null，同时提供 error；不会把失败伪装成无界。JSON Schema 检查十进制字符串形状；Int64 实际范围由生产者类型保证，不由该字符串正则完整证明。

失败和冲突分量的 offsets／intervals 均为 null。可行分量使用同一组参考归零的偏移；区间端点为分别计算的边际范围，不保证能同时取到。

## 证据回查

约束采用 offset(left_clock)-offset(right_clock) <= upper_bound_us，边为 edge_from→edge_to。index 是原始约束数组的零基位置。

1. 读取 components[i].cycle.constraint_indices，按顺序取 constraints 中的原始边。
2. 从消息 evidence 取 send_event_id／receive_event_id，在 events 按 ID 找到观测值和 source。
3. 先验边通过 prior_label 回查 model.priors；bound 标明来自下界还是上界。

环权总和是字符串；minimum_conflict_guaranteed=false 表示不承诺最小冲突集合，不是断言该环一定不最小。负环只证明这些约束不能同时成立，不直接确定故障根因。

错误使用稳定的 code／details，不以 Debug 字符串作为数据契约。求解算术错误包含 phase 与原始 constraint_index；坐标错误包含 clock_id／reference_clock；资源错误保留实际限制。完整输入诊断保留物理 line；未知全局位置用 null。

## 确定性与边界

stringify 递归按 UTF-16 字典序输出对象键；事件表和先验表显式排序，消息和约束数组保留上游稳定顺序。没有导出时间字段。相同源报告与输出选项应生成相同文本；不承诺不同输入顺序一定选择相同负环。

字符串转义交给标准库 JSON 序列化，不直接拼接未转义的事件内容。本层没有新增输出容量限制，较大报告的内存与输出容量尚未测量。

报告不会校验 source 路径对应的磁盘文件，也无法推断上游是否人为修改过时间戳。本机采集的注入数据仍应与其 manifest 一并保存。

## 实现与运行状态

2026-10-20：moon check --target all --deny-warn 通过，公开接口已生成，新包已格式化。通过 native 导出例程实际生成了 6 份可解析的 JSON 示例，覆盖可行、多分量冲突、输入非法、计算未完成、没有约束和本机采集数据。

示例见 [examples/json-report](../examples/json-report/README.md)。本阶段未新增或运行测试套件，也未执行 JSON Schema 实例验证；Schema 不验证引用完整性、图论结论或求解正确性。原核心测试的历史结果见 docs/core-validation.md。
