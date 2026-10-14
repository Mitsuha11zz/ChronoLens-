# input

职责：JSONL 解析、字段校验、重复事件检查与输入资源限制。

## 接口与结果

`parse_jsonl(text, source_path?, limits?)` 返回 `InputReport`。调用方导入 `Mitsuha11zz/chronolens/input`，使用别名 `input`。

入口接收已读入内存的 String；文件读取、字节流解码和 CLI 分析命令在后续适配阶段实现。默认来源路径为 `<memory>`。

| 结果成员 | 契约 |
| --- | --- |
| `accepted_events` | 只读的合法事件预览，保持输入顺序 |
| `issues` | 只读诊断，包含实际输入行号与 IssueKind |
| `status` | Complete 表示扫描完成，Limited(reason) 表示提前停止 |
| `records_seen` | 已尝试解析的非空记录数，包含非法记录 |
| `is_valid()` | 扫描完成且没有诊断时才为真 |
| `validated_events()` | 整份输入有效时返回独立的事件数组，否则返回 None |

有错误的输入可保留合法行用于预览，下游必须通过 `validated_events()` 或 `is_valid()` 检查整份输入。Complete 单独不表示校验通过。

非法配置或来源路径抛出 InputConfigError；输入内容错误进入诊断报告。

## 字段契约

每个非空行是一条 JSON 对象，支持 LF、CRLF、空白行和无末尾换行。多行 JSON 对象不属于本接口支持的 JSONL 记录。

| 字段 | 类型与规则 |
| --- | --- |
| event_id | 必填非空白字符串；合法记录间不可重复 |
| clock_id、trace_id、message_id | 必填非空白字符串 |
| attempt | 必填 JSON 数字，其数值为 0 至 2147483647 的整数 |
| kind | 必填字符串，仅允许 send 或 receive |
| ts_us | 必填十进制整数字符串，可有负号，值在 Int64 范围内 |
| source | 可选对象，含非空白字符串 path 和正整数 line |

attempt 和 source.line 按原始 JSON 数字文本的精确整数值校验。1.0 或 1e0 可表达 1，1.23e2 可表达 123，字符串不会自动转换成数字。接近整数的小数仍被拒绝，即使浮点解析已将它舍入成整数；负数、非零小数的指数下溢和范围溢出均不会变成有效元数据。attempt 允许数值为零的 -0，source.line 必须大于零。

ts_us 严格使用整数解析，不经过浮点数。加号、空格、小数、指数、十六进制和 Int64 溢出均被拒绝。

合法标识保留原文。未知字段、重复 JSON 字段及转义后同名的字段被拒绝，非法 Unicode 形成诊断。

声明的 source 保留为事件来源，诊断始终使用实际输入行号。重复事件 ID 同时记录第一条合法记录的行号；非法行的 ID 不进入合法事件索引，但该错误仍使整份输入无法通过校验。

## 输入限制

使用 InputLimits::new 配置，所有值必须为正数。

| 参数 | 默认值 | 含义 |
| --- | ---: | --- |
| max_input_bytes | 8388608 | 整份文本 UTF-8 字节数，配置硬上限 64 MiB |
| max_line_bytes | 65536 | 物理行 UTF-8 字节数，包含 CRLF 中的 CR |
| max_records | 10000 | 尝试解析的非空行数 |
| max_clock_domains | 64 | 已接受事件中的不同 clock_id 数 |
| max_field_bytes | 4096 | 字符串值及输入来源路径的 UTF-8 字节数 |
| max_issues | 100 | 达到该诊断数后停止扫描 |
| max_json_depth | 16 | 顶层对象深度为 1，配置硬上限 64 |

总字节、行字节、记录、时钟域或诊断数限制会使状态变为 Limited。单条记录的字段长度或结构深度超限生成该行错误，随后继续扫描；整份报告仍然无效。

大小检查采用有界扫描，并验证代理对，不分配整份 UTF-8 编码副本。结构深度在调用 JSON 解析器前检查。字节等边界恰好相等时允许；诊断数恰好达到上限时保守标记为 Limited。

## 验证

34 项输入黑盒测试覆盖四事件样例、CRLF、错误行号、字段契约、精确时间戳、重复 ID、来源、重复字段、Unicode、资源限制、配置硬上限，以及整数元数据的原文校验、舍入边界、指数下溢和转义字段名。

2026-10-14：全项目在 wasm、wasm-gc、js、native 各通过 43/43：34 项输入测试加 9 项基础模型测试。
