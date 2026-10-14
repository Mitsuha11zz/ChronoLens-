///|
test "duplicate object fields are rejected including escaped aliases" {
  let plain =
    #|{"event_id":"first","event_id":"second","clock_id":"A","trace_id":"t","message_id":"m","attempt":0,"kind":"send","ts_us":"0"}
  let escaped =
    #|{"event_id":"first","\u0065vent_id":"second","clock_id":"A","trace_id":"t","message_id":"m","attempt":0,"kind":"send","ts_us":"0"}
  for text in [plain, escaped] {
    let report = @input.parse_jsonl(text)
    assert_eq(report.issues[0].kind, @input.DuplicateField("event_id"))
    assert_eq(report.validated_events(), None)
  }
}

///|
test "duplicate nested source fields are diagnosed" {
  let text =
    #|{"event_id":"e","clock_id":"A","trace_id":"t","message_id":"m","attempt":0,"kind":"send","ts_us":"0","source":{"path":"a","path":"b","line":1}}
  let report = @input.parse_jsonl(text)
  assert_eq(report.issues[0].kind, @input.DuplicateField("path"))
}

///|
test "JSON integer values accept exponent syntax without accepting overflow" {
  let valid =
    #|{"event_id":"e","clock_id":"A","trace_id":"t","message_id":"m","attempt":1e0,"kind":"send","ts_us":"0"}
  let report = @input.parse_jsonl(valid)
  assert_true(report.is_valid())
  assert_eq(report.accepted_events[0].key().attempt(), 1)
  let huge =
    #|{"event_id":"e","clock_id":"A","trace_id":"t","message_id":"m","attempt":1e100,"kind":"send","ts_us":"0"}
  assert_eq(
    @input.parse_jsonl(huge).issues[0].kind,
    @input.InvalidValue("attempt"),
  )
}

///|
test "total input size counts multibyte Unicode exactly" {
  let text =
    #|{"event_id":"中😀","clock_id":"A","trace_id":"t","message_id":"m","attempt":0,"kind":"send","ts_us":"0"}
  // Chinese character: 3 UTF-8 bytes vs 1 UTF-16 unit;
  // emoji: 4 UTF-8 bytes vs 2 UTF-16 units. All other characters are ASCII.
  let bytes = text.length() + 4
  let exact = @input.InputLimits::new(max_input_bytes=bytes)
  assert_true(@input.parse_jsonl(text, limits=exact).is_valid())
  let smaller = @input.InputLimits::new(max_input_bytes=bytes - 1)
  assert_eq(
    @input.parse_jsonl(text, limits=smaller).status,
    @input.Limited("max_input_bytes"),
  )
}

///|
test "resource policies have bounded hard ceilings" {
  try @input.InputLimits::new(max_json_depth=65) catch {
    err => assert_eq(err, @input.InvalidLimit("max_json_depth"))
  } noraise {
    _ => fail("expected nesting hard-cap error")
  }
  try @input.InputLimits::new(max_input_bytes=67108865) catch {
    err => assert_eq(err, @input.InvalidLimit("max_input_bytes"))
  } noraise {
    _ => fail("expected input hard-cap error")
  }
}

///|
test "fractional numeric metadata must not become integers through rounding" {
  let fractional =
    #|{"event_id":"e","clock_id":"A","trace_id":"t","message_id":"m","attempt":0.99999999999999999999,"kind":"send","ts_us":"0"}
  let report = @input.parse_jsonl(fractional)
  assert_true(!report.is_valid())
  assert_eq(report.issues[0].kind, @input.InvalidValue("attempt"))
}
