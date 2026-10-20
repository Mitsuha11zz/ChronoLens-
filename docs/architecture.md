# 包职责与依赖规划

model、input、correlate、constraints、solver 的核心分析及 report 的 JSON 导出已实现；其余能力的依赖仍为后续规划。

| 包 | 职责 | 拟依赖 |
| --- | --- | --- |
| 根包 | 公开端到端入口与能力组合 | input、correlate、constraints、solver、report |
| model | 公共事件、约束、配置和结果类型 | 标准库 |
| input | JSONL 解析、字段校验、资源限制 | model |
| correlate | 按消息键配对，报告缺失与歧义；输入报告门控入口 | model、input |
| constraints | 将唯一消息对与显式偏移先验转为差分约束，保留未解决证据 | model、correlate |
| solver | 全图可行性、负环见证、参考坐标下的偏移区间与独立分量分析 | model、constraints |
| report | 已实现 JSON 诊断导出；Markdown 待实现 | model、input、correlate、constraints、solver |
| cmd/chronolens | 参数、文件 IO 与退出码 | 根包、report |
| demo | 浏览器中的结果与证据展示 | 经验证的核心后端或结果适配层 |
| examples/two-services | Python 标准库采集本机双进程 TCP 记录，转换后由 native 样例入口调用核心分析 | input、correlate、constraints、solver、core/env |
| examples/json-report | native JSON 报告导出例程 | input、correlate、constraints、solver、report、core/env |

`model/` 是公开包，用户需要构造、匹配或调用方法的公共类型由该包持有。后续增加内部扫描器等辅助包时，不将公共具体类型迁入 `internal/`。

输入、IO 和展示与求解算法分开；算法接收结构化数据并返回结构化结果。所有时间值采用有溢出检查的 64 位整数运算。

固定定义：`模型时间 = 原始时间 + 时钟偏移`。约束 `o_i - o_j <= c` 转换为边 `j -> i`、权重 `c`。区间与冲突结论均受输入关联和固定偏移假设约束。
