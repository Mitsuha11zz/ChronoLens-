///|
test "validated four-event JSONL input yields two evidence-preserving pairs" {
  let text =
    #|{"event_id":"a1","clock_id":"A","trace_id":"t1","message_id":"request-1","attempt":0,"kind":"send","ts_us":"1000000"}
    #|{"event_id":"b1","clock_id":"B","trace_id":"t1","message_id":"request-1","attempt":0,"kind":"receive","ts_us":"900000"}
    #|{"event_id":"b2","clock_id":"B","trace_id":"t1","message_id":"response-1","attempt":0,"kind":"send","ts_us":"940000"}
    #|{"event_id":"a2","clock_id":"A","trace_id":"t1","message_id":"response-1","attempt":0,"kind":"receive","ts_us":"1100000"}
  let input = @input.parse_jsonl(text, source_path="four-events.jsonl")
  let report = @correlate.correlate_input(input)
  assert_true(report.fully_paired())
  assert_eq(report.stats.total_events, 4)
  assert_eq(report.stats.paired_groups, 2)
  assert_eq(report.pairs[0].send_event.event_id(), "a1")
  assert_eq(report.pairs[0].receive_event.event_id(), "b1")
  assert_eq(report.pairs[1].send_event.event_id(), "b2")
  assert_eq(report.pairs[1].receive_event.event_id(), "a2")
  assert_eq(report.pairs[1].receive_event.source().unwrap().line(), 4)
  assert_eq(
    report.pairs[1].receive_event.source().unwrap().path(),
    "four-events.jsonl",
  )
}

///|
test "invalid and truncated input reports cannot enter the pipeline" {
  let send =
    #|{"event_id":"s","clock_id":"A","trace_id":"t","message_id":"m","attempt":0,"kind":"send","ts_us":"0"}
  let receive =
    #|{"event_id":"r","clock_id":"B","trace_id":"t","message_id":"m","attempt":0,"kind":"receive","ts_us":"0"}
  let invalid = @input.parse_jsonl(send + "\n{bad}\n" + receive)
  assert_eq(invalid.accepted_events.length(), 2)
  let truncated = @input.parse_jsonl(
    send + "\n" + receive,
    limits=@input.InputLimits::new(max_records=1),
  )
  for input in [invalid, truncated] {
    try @correlate.correlate_input(input) catch {
      err => assert_eq(err, @correlate.InvalidInput)
    } noraise {
      _ => fail("expected invalid input rejection")
    }
  }
}
