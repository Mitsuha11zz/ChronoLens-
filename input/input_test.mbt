///|
fn fields(
  id? : String = "e1",
  clock? : String = "A",
  ts? : String = "1000000",
) -> Map[String, Json] {
  {
    "event_id": Json::string(id),
    "clock_id": Json::string(clock),
    "trace_id": Json::string("t1"),
    "message_id": Json::string("m1"),
    "attempt": Json::number(0.0),
    "kind": Json::string("send"),
    "ts_us": Json::string(ts),
  }
}

///|
fn record(
  id? : String = "e1",
  clock? : String = "A",
  ts? : String = "1000000",
) -> String {
  Json::object(fields(id~, clock~, ts~)).stringify()
}

///|
test "four-event request response example preserves exact observations" {
  let a1 = record(id="a1", ts="1000000")
  let b1 = fields(id="b1", clock="B", ts="900000")
  b1["kind"] = Json::string("receive")
  let b2 = fields(id="b2", clock="B", ts="940000")
  b2["message_id"] = Json::string("response-1")
  let a2 = fields(id="a2", ts="1100000")
  a2["kind"] = Json::string("receive")
  a2["message_id"] = Json::string("response-1")
  let lines = [
    a1,
    Json::object(b1).stringify(),
    Json::object(b2).stringify(),
    Json::object(a2).stringify(),
  ]
  let report = @input.parse_jsonl(lines.join("\n"), source_path="sample.jsonl")
  assert_true(report.is_valid())
  assert_eq(report.records_seen, 4)
  assert_eq(report.issues.length(), 0)
  let events = report.validated_events().unwrap()
  assert_eq(events.length(), 4)
  assert_eq(events.map(e => e.timestamp_us()), [
    1000000L, 900000L, 940000L, 1100000L,
  ])
  assert_eq(events[1].kind(), @model.Receive)
  assert_eq(events[2].key().message_id(), "response-1")
  assert_eq(events[3].source().unwrap().line(), 4)
  assert_eq(events[3].source().unwrap().path(), "sample.jsonl")
  events.clear()
  assert_eq(report.accepted_events.length(), 4)
}

///|
test "blank lines and CRLF preserve physical line locations" {
  let report = @input.parse_jsonl(
    " \t\r\n" + record() + "\r\n\n" + record(id="e2"),
  )
  assert_true(report.is_valid())
  assert_eq(report.records_seen, 2)
  assert_eq(report.accepted_events[0].source().unwrap().line(), 2)
  assert_eq(report.accepted_events[1].source().unwrap().line(), 4)
}

///|
test "empty and whitespace-only input do not appear analysis-ready" {
  for text in ["", "\r\n \t\n"] {
    let report = @input.parse_jsonl(text)
    assert_true(!report.is_valid())
    assert_eq(report.issues[0].kind, @input.EmptyInput)
    assert_eq(report.validated_events(), None)
  }
}

///|
test "bad JSON produces located diagnostics and allows later valid previews" {
  let report = @input.parse_jsonl("{bad}\n" + record())
  assert_eq(report.status, @input.Complete)
  assert_eq(report.issues[0].line, Some(1))
  assert_eq(report.issues[0].kind, @input.InvalidJson)
  assert_eq(report.accepted_events.length(), 1)
  assert_eq(report.validated_events(), None)
}

///|
test "records must be JSON objects" {
  for text in ["[]", "true", "null", "123", "\"text\""] {
    let report = @input.parse_jsonl(text)
    assert_eq(report.issues[0].kind, @input.ExpectedObject)
  }
}

///|
test "each required field is diagnosed by name" {
  for
    name in [
      "event_id", "clock_id", "trace_id", "message_id", "attempt", "kind", "ts_us",
    ] {
    let object = fields()
    object.remove(name)
    let report = @input.parse_jsonl(Json::object(object).stringify())
    assert_eq(report.issues[0].kind, @input.MissingField(name))
    assert_eq(report.accepted_events.length(), 0)
  }
}

///|
test "wrong field types are rejected without coercion" {
  for
    name in ["event_id", "clock_id", "trace_id", "message_id", "kind", "ts_us"] {
    let object = fields()
    object[name] = Json::number(1.0)
    let report = @input.parse_jsonl(Json::object(object).stringify())
    assert_eq(report.issues[0].kind, @input.WrongType(name))
  }
  let object = fields()
  object["attempt"] = Json::string("0")
  assert_eq(
    @input.parse_jsonl(Json::object(object).stringify()).issues[0].kind,
    @input.WrongType("attempt"),
  )
}

///|
test "blank identities are rejected but legal identity text is preserved" {
  for name in ["event_id", "clock_id", "trace_id", "message_id"] {
    let object = fields()
    object[name] = Json::string(" \t")
    assert_eq(
      @input.parse_jsonl(Json::object(object).stringify()).issues[0].kind,
      @input.InvalidValue(name),
    )
  }
  let report = @input.parse_jsonl(record(id=" 事件😀 "))
  assert_true(report.is_valid())
  assert_eq(report.accepted_events[0].event_id(), " 事件😀 ")
}

///|
test "kinds and retry indexes have strict syntax and range" {
  let object = fields()
  object["kind"] = Json::string("SEND")
  assert_eq(
    @input.parse_jsonl(Json::object(object).stringify()).issues[0].kind,
    @input.InvalidValue("kind"),
  )
  for number in ["-1", "0.5", "2147483648"] {
    let object = fields()
    object["attempt"] = @json.parse(number)
    assert_eq(
      @input.parse_jsonl(Json::object(object).stringify()).issues[0].kind,
      @input.InvalidValue("attempt"),
    )
  }
  for number in ["1e0", "1.0"] {
    let object = fields()
    object["attempt"] = @json.parse(number)
    let report = @input.parse_jsonl(Json::object(object).stringify())
    assert_true(report.is_valid())
    assert_eq(report.accepted_events[0].key().attempt(), 1)
  }
}

///|
test "timestamps are exact above double precision and at both Int64 boundaries" {
  for
    (text, expected) in [
      ("9007199254740993", 9007199254740993L),
      ("9223372036854775807", 9223372036854775807L),
      ("-9223372036854775808", -9223372036854775807L - 1L),
      ("-1", -1L),
      ("0", 0L),
    ] {
    let report = @input.parse_jsonl(record(ts=text))
    assert_true(report.is_valid())
    assert_eq(report.accepted_events[0].timestamp_us(), expected)
  }
}

///|
test "timestamp overflow and nondecimal forms are rejected" {
  for
    text in [
      "9223372036854775808", "-9223372036854775809", "", "-", "+1", "1e3", "1.0",
      " 1", "1 ", "0x10", "１２",
    ] {
    let report = @input.parse_jsonl(record(ts=text))
    assert_eq(report.issues[0].kind, @input.InvalidValue("ts_us"))
    assert_eq(report.validated_events(), None)
  }
}

///|
test "duplicate event ids retain first physical line and exclude duplicate" {
  let report = @input.parse_jsonl(
    record() + "\n\n" + record() + "\n" + record(id="e2"),
  )
  assert_eq(report.issues[0].line, Some(3))
  assert_eq(report.issues[0].kind, @input.DuplicateEventId(first_line=1))
  assert_eq(report.accepted_events.length(), 2)
  assert_eq(report.records_seen, 3)
  assert_true(!report.is_valid())
}

///|
test "declared sources are retained but diagnostics use physical lines" {
  let object = fields()
  object["source"] = Json::object({
    "path": Json::string("original.log"),
    "line": Json::number(42.0),
  })
  let line = Json::object(object).stringify()
  let good = @input.parse_jsonl(line)
  assert_eq(good.accepted_events[0].source().unwrap().path(), "original.log")
  assert_eq(good.accepted_events[0].source().unwrap().line(), 42)
  let bad = @input.parse_jsonl(line + "\n" + line)
  assert_eq(bad.issues[0].line, Some(2))
  assert_eq(bad.issues[0].kind, @input.DuplicateEventId(first_line=1))
}

///|
test "source object validates required fields and one-based line" {
  for
    (source, expected) in [
      (Json::null(), @input.WrongType("source")),
      (
        Json::object({ "path": Json::string("x") }),
        @input.MissingField("source.line"),
      ),
      (
        Json::object({ "path": Json::number(0.0), "line": Json::number(1.0) }),
        @input.WrongType("source.path"),
      ),
      (
        Json::object({ "path": Json::string("x"), "line": Json::number(0.0) }),
        @input.InvalidValue("source.line"),
      ),
    ] {
    let object = fields()
    object["source"] = source
    assert_eq(
      @input.parse_jsonl(Json::object(object).stringify()).issues[0].kind,
      expected,
    )
  }
}

///|
test "unknown top-level and source fields are rejected" {
  let object = fields()
  object["typo"] = Json::null()
  assert_eq(
    @input.parse_jsonl(Json::object(object).stringify()).issues[0].kind,
    @input.UnknownField("typo"),
  )
  object.remove("typo")
  object["source"] = Json::object({
    "path": Json::string("x"),
    "line": Json::number(1.0),
    "typo": Json::null(),
  })
  assert_eq(
    @input.parse_jsonl(Json::object(object).stringify()).issues[0].kind,
    @input.UnknownField("source.typo"),
  )
}

///|
test "input byte limit accepts exact ASCII boundary and rejects one byte more" {
  let text = record()
  let exact = @input.InputLimits::new(max_input_bytes=text.length())
  assert_true(@input.parse_jsonl(text, limits=exact).is_valid())
  let smaller = @input.InputLimits::new(max_input_bytes=text.length() - 1)
  let report = @input.parse_jsonl(text, limits=smaller)
  assert_eq(report.status, @input.Limited("max_input_bytes"))
  assert_eq(report.records_seen, 0)
  assert_eq(report.validated_events(), None)
}

///|
test "line byte limit is enforced before decoding" {
  let text = record()
  assert_true(
    @input.parse_jsonl(
      text,
      limits=@input.InputLimits::new(max_line_bytes=text.length()),
    ).is_valid(),
  )
  let report = @input.parse_jsonl(
    text,
    limits=@input.InputLimits::new(max_line_bytes=text.length() - 1),
  )
  assert_eq(report.status, @input.Limited("max_line_bytes"))
  assert_eq(report.issues[0].line, Some(1))
}

///|
test "record cap counts invalid rows and ignores blank rows" {
  let report = @input.parse_jsonl(
    "bad\n\n" + record(),
    limits=@input.InputLimits::new(max_records=1),
  )
  assert_eq(report.records_seen, 1)
  assert_eq(report.status, @input.Limited("max_records"))
  assert_eq(report.issues[1].line, Some(3))
  assert_eq(report.accepted_events.length(), 0)
}

///|
test "clock cap only counts new clock domains" {
  let text = record() +
    "\n" +
    record(id="e2") +
    "\n" +
    record(id="e3", clock="B")
  let report = @input.parse_jsonl(
    text,
    limits=@input.InputLimits::new(max_clock_domains=1),
  )
  assert_eq(report.accepted_events.length(), 2)
  assert_eq(report.status, @input.Limited("max_clock_domains"))
  assert_eq(report.validated_events(), None)
}

///|
test "issue cap stops parsing without treating preview as valid" {
  let report = @input.parse_jsonl(
    "bad\n" + record(),
    limits=@input.InputLimits::new(max_issues=1),
  )
  assert_eq(report.issues.length(), 1)
  assert_eq(report.records_seen, 1)
  assert_eq(report.status, @input.Limited("max_issues"))
  assert_eq(report.validated_events(), None)
}

///|
test "field limits count Unicode UTF-8 bytes" {
  let limits = @input.InputLimits::new(max_field_bytes=7)
  assert_true(
    @input.parse_jsonl(record(id="中😀"), source_path="x", limits~).is_valid(),
  )
  let report = @input.parse_jsonl(
    record(id="中😀a"),
    source_path="x",
    limits~,
  )
  assert_eq(report.issues[0].kind, @input.LimitExceeded("max_field_bytes"))
  assert_eq(report.validated_events(), None)
}

///|
test "depth cap ignores braces and escaped quotes inside strings" {
  let limits = @input.InputLimits::new(max_json_depth=1)
  let report = @input.parse_jsonl(record(id="e{\"}[\\]"), limits~)
  assert_true(report.is_valid())
  let object = fields()
  object["source"] = Json::object({
    "path": Json::string("x"),
    "line": Json::number(1.0),
  })
  let deep = @input.parse_jsonl(Json::object(object).stringify(), limits~)
  assert_eq(deep.issues[0].kind, @input.LimitExceeded("max_json_depth"))
}

///|
test "malformed escaped Unicode produces diagnostics rather than a panic" {
  let text =
    #|{"event_id":"\ud800","clock_id":"A","trace_id":"t","message_id":"m","attempt":0,"kind":"send","ts_us":"0"}
  let report = @input.parse_jsonl(text)
  assert_true(!report.is_valid())
  assert_eq(report.accepted_events.length(), 0)
}

///|
test "invalid configuration and input source path raise typed errors" {
  try @input.InputLimits::new(max_records=0) catch {
    err => assert_eq(err, @input.InvalidLimit("max_records"))
  } noraise {
    _ => fail("expected invalid limit")
  }
  try @input.InputLimits::new(max_input_bytes=-1) catch {
    err => assert_eq(err, @input.InvalidLimit("max_input_bytes"))
  } noraise {
    _ => fail("expected invalid limit")
  }
  try @input.parse_jsonl(record(), source_path=" \t") catch {
    err => assert_eq(err, @input.InvalidSourcePath)
  } noraise {
    _ => fail("expected invalid source path")
  }
}
