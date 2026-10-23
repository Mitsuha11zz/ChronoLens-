# 本机双进程请求／响应样例

这是可运行的采集与输入转换示例：调用方 A 和服务端 B 是两个独立 Python 进程，通过实际的 127.0.0.1 TCP 连接传递请求／响应。时间约束求解仍由 MoonBit 核心完成。

已于 2026-10-20 实际运行并归档一份采集。此样例证明消息身份与发送／接收记录可以从运行中的程序获得；不代表已验证真实多机器时钟或生产系统。

## 1. 运行

本次环境为 Python 3.13.9 和 moon 0.1.20261012。Python 代码只使用标准库；MoonBit 样例入口仅支持 native。

从仓库根目录执行：

~~~text
python examples/two-services/run.py --analyze
~~~

默认进行 3 次请求／响应，在新的 runs/<随机标识>/ 目录中保存数据。runs/ 已被 Git 忽略。监听地址固定为 127.0.0.1，端口由操作系统分配；采集完成后两个子进程退出，监听结束。脚本仅清理自己启动且尚未退出的子进程。

参数：

| 参数 | 含义 |
| --- | --- |
| --requests | 请求次数，默认 3，范围 1..16 |
| --processing-ms | B 每次响应前请求的等待时间，默认 10，范围 0..200；不是测得的处理耗时 |
| --b-shift-us | 仅转换副本中 B 时间戳的增量，默认 -120000 微秒 |
| --out | 指定新的采集目录；已存在的目录一律拒绝 |
| --analyze | 采集、转换后调用 MoonBit 核心分析 |
| --replay | 核对归档输入哈希并只读重放，不重新采集或改写归档 |

重放仓库中已经采集的样例：

~~~text
python examples/two-services/run.py --replay examples/two-services/sample
~~~

分析样例通过有长度上限的环境变量传递 JSONL 给 MoonBit native 入口，不生成代码文件。数据过大时要求减少请求数；这是当前采集脚本样例的数据桥接方式。正式文件分析请使用 [ChronoLens CLI](../../cmd/chronolens/README.md)。

## 2. 采集内容

| 文件 | 内容 |
| --- | --- |
| service-a.raw.jsonl | A 的实际请求发送与响应接收记录 |
| service-b.raw.jsonl | B 的实际请求接收与响应发送记录 |
| ready.json | 采集时 B 的进程 ID 和临时监听端口，不表示当前仍在运行 |
| events.original.jsonl | 未注入偏移的 ChronoLens 格式事件 |
| events.shifted.jsonl | 只改变 B 时间戳后的事件副本 |
| manifest.json | 进程、配置、四份输入的 SHA-256、注入值及样例分析摘要 |
| analysis.original.txt | 未注入数据的 MoonBit 输出 |
| analysis.shifted.txt | 已注入数据的 MoonBit 输出 |

原始文件不因注入而改变。两个事件文件保留相同的事件 ID、消息键及 source；source 指向原始文件名与实际行号。使用已注入文件时应一并保留 manifest，才能解释其时间戳与原始来源的差值。

## 3. 消息身份与采样位置

A 在协议中发送 trace_id、request_id、response_id 和 attempt，B 在响应中原样传回身份字段，A 核对响应对应的请求。每次请求有独立 trace，发送／接收的 message_id 取自实际协议字段；不通过时间接近程度或任意文本匹配猜测关联。

| 原始 phase | 服务角色 | ChronoLens kind | message_id 来源 |
| --- | --- | --- | --- |
| request_send | A | send | request_id |
| request_receive | B | receive | request_id |
| response_send | B | send | response_id |
| response_receive | A | receive | response_id |

发送时间在调用 socket.sendall 之前记录；接收时间在完整读取并解析一个消息帧之后记录。使用 time.time_ns() // 1000，按精确十进制字符串保存 Unix 微秒时间。记录写入、解析与调度开销会进入可行区间，不能将区间宽度解释为纯网络延迟。

A、B 使用同一台机器的系统时钟，所以原始采集预期包含零相对偏移。这里保留两个 clock_id 是为了演示后续独立时钟域的输入。若采集期间系统时钟发生跳变，原始约束也可能不满足该预期，脚本会停止并保留原始数据，不自动修改记录。

## 4. 单独使用转换器

转换器只支持本例 chronolens.local-rpc.v1 格式。父目录必须存在，输出文件必须尚不存在。例如在运行 MoonBit 样例后：

~~~text
python examples/two-services/convert.py --raw-a examples/two-services/sample/service-a.raw.jsonl --raw-b examples/two-services/sample/service-b.raw.jsonl --out _build/converted-local.jsonl --b-shift-us 0
~~~

转换器检查字段、重复 JSON 键、消息标识、单一进程身份、phase 对应的角色、精确整数时间戳、Int64 范围和重复事件；每份原始文件上限为 8 MiB。它不补造缺失消息，也不根据时间排序来建立关联。合并后的行顺序不代表事件因果顺序。

对于真实业务系统，需要上游明确记录相同语义的消息身份与采样位置，或另写有文档约定的适配器。本例不是任意日志格式的自动适配器。

## 5. 本次实际归档结果

仓库 sample/ 保留本次真实本机采集的原始数据，而不是手工构造的四事件数据。

- 请求／响应：3 次，形成 6 个一发一收消息、12 条事件。
- 独立进程：A=50152，B=53924；进程 ID 只是该次采集的运行元数据。
- 参考时钟：A；关系容差：0；没有额外偏移先验。

| 数据 | B 下界（微秒） | B 上界（微秒） | 一组代表偏移 B（微秒） |
| --- | ---: | ---: | ---: |
| 原始采集 | -69 | 109 | 0 |
| B 时间戳统一减去 120000 微秒 | 119931 | 120109 | 119931 |

原始范围包含零。注入后，模型补偿值为 +120000 微秒，落在新的范围内；上下界恰好都比原始值增加 120000。代表偏移不是唯一真值，所以返回的代表偏移可以不是 120000。

重新采集时绝对时间、进程 ID 和区间可能不同；只读重放已归档输入时，应得到上述相同区间。原始采集、转换、MoonBit 分析及归档重放均已实际运行；本阶段没有新增或执行测试套件，也没有测量生产容量。

## 6. 后续范围

正式 JSON／Markdown 诊断报告与文件分析 CLI 已提供。多机器采集仍未验证；OpenTelemetry RPC trace 转换见[适配器文档](../otel-rpc/README.md)，其它真实日志格式需按其事件语义另行设计适配器。
