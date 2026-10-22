# ChronoLens CLI

正式命令行入口读取 ChronoLens JSONL 事件文件，执行输入校验、消息关联、差分约束构建和偏移分析，然后输出诊断报告。

## 使用

在仓库根目录运行：

```text
moon run cmd/chronolens -- fixtures/four-events.jsonl
moon run cmd/chronolens -- fixtures/four-events.jsonl --format markdown
moon run cmd/chronolens -- fixtures/four-events.jsonl --output report.json
moon run cmd/chronolens -- fixtures/four-events.jsonl --reference-clock service-a --relation-tolerance-us 50
```

默认输出缩进 JSON 到标准输出。`--format` 可选 `json` 或 `markdown`；`--output` 将报告写入文件。已有输出文件默认不会被覆盖，明确传入 `--force` 后才会替换。

输入字段与时间单位见 [JSONL 输入契约](../../input/README.md)。报告字段与语义见 [诊断报告契约](../../report/README.md)。

## 限制参数

输入限制的默认值与 `InputLimits::default()` 相同：最大文件 8 MiB、单行 64 KiB、10,000 条记录、64 个时钟域、单字段 4 KiB、100 条诊断和 JSON 深度 16。可通过 `--max-input-bytes`、`--max-line-bytes`、`--max-records`、`--max-clock-domains`、`--max-field-bytes`、`--max-issues`、`--max-json-depth` 覆盖。文件字节数会在读取前预检；读取后还会复核实际字节数。

求解限制默认最多 256 个时钟、20,000 条约束和 5,000,000 次边访问。可通过 `--max-clocks`、`--max-constraints`、`--max-edge-visits` 调整。输入限制和求解限制仍受核心库的硬上限约束。`--relation-tolerance-us` 设定非负消息关系容差；`--reference-clock` 指定参考时钟坐标。

## 退出状态

| 状态码 | 含义 |
| --- | --- |
| `0` | 分析完成，未发现冲突 |
| `1` | 分析完成，至少一个分量存在约束冲突 |
| `2` | 命令行参数、限制配置或输出目标无效 |
| `3` | 输入读取或报告写入失败 |
| `4` | 输入非法、UTF-8 无效或超过输入大小限制 |
| `5` | 关联／约束／求解阶段失败，或分析结果不完整 |

输入非法但能生成诊断时，报告仍会输出，退出码为 `4`。求解器输出已知冲突时退出码为 `1`，即使其他分量计算失败；未能确定冲突状态时退出码为 `5`。错误说明写入标准错误，报告写入标准输出或指定文件。

当前文件大小预检只支持 native CLI；CLI 包限定在 native target。此预检与读取后的字节数复核一起处理文件大小边界。
