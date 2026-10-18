///|
/// Fixture data embedded from fixtures/mixed-associations.jsonl for all backends.
fn mixed_fixture() -> String {
  let text =
    #|{"event_id":"a-send","clock_id":"A","trace_id":"t","message_id":"a","attempt":0,"kind":"send","ts_us":"0"}
    #|{"event_id":"b-send","clock_id":"A","trace_id":"t","message_id":"b","attempt":0,"kind":"send","ts_us":"0"}
    #|{"event_id":"a-recv","clock_id":"B","trace_id":"t","message_id":"a","attempt":0,"kind":"receive","ts_us":"10"}
    #|{"event_id":"c-send-2","clock_id":"A","trace_id":"t","message_id":"c","attempt":0,"kind":"send","ts_us":"100"}
    #|{"event_id":"c-recv","clock_id":"B","trace_id":"t","message_id":"c","attempt":0,"kind":"receive","ts_us":"110"}
    #|{"event_id":"c-send-1","clock_id":"A","trace_id":"t","message_id":"c","attempt":0,"kind":"send","ts_us":"0"}
  text
}

///|
test "unresolved groups preserve all clocks without fabricated edges" {
  let input = @input.parse_jsonl(
    mixed_fixture(),
    source_path="mixed-associations.jsonl",
  )
  assert_true(input.is_valid())
  let correlation = @correlate.correlate_input(input)
  let built = @constraints.build(correlation)
  assert_eq(built.constraints.length(), 1)
  assert_eq(built.correlation.unresolved.length(), 2)
  let expected : Map[String, Unit] = Map([])
  for event in input.accepted_events {
    expected[event.clock_id()] = ()
  }
  assert_eq(built.clocks.length(), expected.length())
  for clock in built.clocks {
    assert_true(expected.contains(clock))
  }
  assert_eq(built.correlation, correlation)
}

///|
test "caller mutations cannot change built prior evidence" {
  let prior = @constraints.OffsetPrior::new(
    clock_id="B",
    reference_clock="A",
    label="p",
    upper_us=5L,
  )
  let priors = [prior]
  let result = @constraints.build(@correlate.correlate([]), priors~)
  priors.clear()
  assert_eq(result.constraints.length(), 1)
  assert_eq(
    result.constraints[0].evidence,
    @constraints.Prior(prior~, lower_bound=false),
  )
}
