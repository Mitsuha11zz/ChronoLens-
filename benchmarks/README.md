# ChronoLens 容量基准

`capacity.py` 使用 Python 标准库生成确定规模的 JSONL 消息记录，并调用正式 native CLI。脚本会先运行一次 `moon build cmd/chronolens --target native --deny-warn`；构建时间不计入基准。也可以用 `--binary` 指定已经构建好的 CLI。

从仓库根目录运行：

```text
python benchmarks/capacity.py
python benchmarks/capacity.py --messages 100,1000 --repeats 5 --warmups 1
python benchmarks/capacity.py --binary _build/native/debug/build/cmd/chronolens/chronolens.exe
```

默认规模为 100、1,000 和 5,000 条消息，每档先预热 1 次，再测量 3 次。每条消息生成一条发送事件和一条接收事件，所以最大默认规模为 10,000 条输入记录，正好等于 CLI 默认记录限制。自定义消息数必须在 1 到 5,000 之间。

结果以 JSON 写到标准输出，包含各次墙钟耗时、中位数、输入字节数和事件每秒处理量。耗时包括 native CLI 进程启动、文件读取、输入解析、关联、约束分析、报告序列化和报告文件写入；不包括编译与输入生成。临时输入和报告在系统临时目录中创建并自动清理。可用 `> capacity-results.json` 将结果保存到本地文件。

每档使用两个时钟域、一个连通分量和全部成功配对的消息；时间差固定，确保工作负载没有冲突。结果适合在同一机器、相同运行条件下比较版本变化，不测峰值内存，不能代表更多时钟域、其他图结构、OTLP 转换或生产容量。
