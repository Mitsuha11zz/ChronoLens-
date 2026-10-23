# 诊断报告导出例程

该例程从环境变量接收 JSONL，调用输入、配对、约束构建、分量求解和 report 包，向标准输出写入诊断 JSON 或 Markdown。处理文件时请使用[正式分析 CLI](../../cmd/chronolens/README.md)。

从仓库根目录运行（PowerShell）：

~~~powershell
$env:CHRONOLENS_REPORT_INPUT = Get-Content -Raw fixtures/four-events.jsonl
moon run examples/json-report --target native
~~~

默认输出格式是带缩进的 JSON。设置格式变量可输出 Markdown：

~~~powershell
$env:CHRONOLENS_REPORT_FORMAT = "markdown"
moon run examples/json-report --target native
Remove-Item Env:CHRONOLENS_REPORT_FORMAT
~~~

示例的解析来源名固定为 report-example.jsonl；事件中已有的 source 保持原值。使用命令行环境桥传入的数据应保持小规模，避免操作系统环境变量长度限制。

## 已生成的 JSON 输出

| 输出文件 | 输入来源 | 实际 status |
| --- | --- | --- |
| outputs/feasible.json | fixtures/four-events.jsonl | feasible |
| outputs/mixed.json | fixtures/component-analysis.jsonl | infeasible |
| outputs/invalid.json | inputs/invalid.jsonl，故意非法的合成输入 | input_invalid |
| outputs/incomplete.json | inputs/overflow.jsonl，故意触发路径溢出的合成输入 | analysis_incomplete |
| outputs/no-constraints.json | inputs/no-constraints.jsonl，只有一个未配对事件 | no_constraints |
| outputs/local-capture.json | examples/two-services/sample/events.shifted.jsonl | feasible |

2026-10-20 已使用 native 例程生成这些文件，并用 JSON 解析器读取。输入来自已有样例或明确标记的合成数据；这不是新一轮实际服务采集。

feasible.json 中 B 的区间为 [100000,160000] 微秒。mixed.json 同时保留三个可行分量及 F 的负环；D 的上界标记 unbounded。incomplete.json 的 has_conflicts 为 null，分量错误为 arithmetic_overflow，不会输出可行区间。no-constraints.json 保留 Int64 最大值时间戳字符串 9223372036854775807 和缺失接收诊断。

local-capture.json 中 B 的区间为 [119931,120109] 微秒。它使用上阶段归档的已注入数据，注入说明仍保存在双进程样例的 manifest.json；JSON 报告不会凭事件自行推断注入历史。

结构与 API 契约见 [report/README.md](../../report/README.md)。JSON 示例使用 native 例程生成；Markdown 可按上面的环境变量命令即时输出。本阶段未新增或运行测试套件。
