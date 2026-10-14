///|
fn metadata_record(literal : String, source_line? : Bool = false) -> String {
  let numeric_field = if source_line {
    "\"attempt\":0,\"source\":{\"path\":\"x\",\"line\":" + literal + "},"
  } else {
    "\"attempt\":" + literal + ","
  }
  "{\"event_id\":\"e\",\"clock_id\":\"A\",\"trace_id\":\"t\",\"message_id\":\"m\"," +
  numeric_field +
  "\"kind\":\"send\",\"ts_us\":\"0\"}"
}

///|
test "exact integer metadata accepts mathematically integral decimals" {
  for
    (literal, expected) in [
      ("0", 0),
      ("-0", 0),
      ("-0.0", 0),
      ("0e1000", 0),
      ("1.0000000000000000000000000", 1),
      ("1e+0", 1),
      ("1.23e2", 123),
      ("100e-2", 1),
      ("0.001e3", 1),
      ("2147483647", 2147483647),
      ("2147483647.00000000", 2147483647),
      ("21474836470e-1", 2147483647),
      ("214748364.7e1", 2147483647),
    ] {
    let report = @input.parse_jsonl(metadata_record(literal))
    assert_true(report.is_valid())
    assert_eq(report.accepted_events[0].key().attempt(), expected)
  }
}

///|
test "fractional underflow and rounded boundary values stay invalid" {
  for
    literal in [
      "0.99999999999999999999", "1.00000000000000000001", "2147483647.00000001",
      "1e-1000", "-1e-1000", "-0.000000000000000000000001", "123e-2", "1e1000", "2147483648",
      "214748364800e-2",
    ] {
    let report = @input.parse_jsonl(metadata_record(literal))
    assert_true(!report.is_valid())
    assert_eq(report.issues[0].kind, @input.InvalidValue("attempt"))
    assert_eq(report.validated_events(), None)
  }
}

///|
test "declared source line uses the same exact integer interpretation" {
  let report = @input.parse_jsonl(metadata_record("1.23e2", source_line=true))
  assert_true(report.is_valid())
  assert_eq(report.accepted_events[0].source().unwrap().line(), 123)
  for
    literal in [
      "0.99999999999999999999", "1.00000000000000000001", "0", "-0", "2147483648",
    ] {
    let invalid = @input.parse_jsonl(metadata_record(literal, source_line=true))
    assert_true(!invalid.is_valid())
    assert_eq(invalid.issues[0].kind, @input.InvalidValue("source.line"))
  }
}

///|
test "escaped numeric field names use original numeric tokens" {
  let valid =
    #|{"event_id":"e","clock_id":"A","trace_id":"t","message_id":"m","\u0061ttempt":100e-2,"kind":"send","ts_us":"0","source":{"path":"x","\u006cine":1e0}}
  let report = @input.parse_jsonl(valid)
  assert_true(report.is_valid())
  assert_eq(report.accepted_events[0].key().attempt(), 1)
  assert_eq(report.accepted_events[0].source().unwrap().line(), 1)
  let invalid =
    #|{"event_id":"e","clock_id":"A","trace_id":"t","message_id":"m","\u0061ttempt":0.99999999999999999999,"kind":"send","ts_us":"0"}
  assert_eq(
    @input.parse_jsonl(invalid).issues[0].kind,
    @input.InvalidValue("attempt"),
  )
}
