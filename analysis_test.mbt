///|
fn facade_field(value : Json?, name : String) -> Json? {
  match value {
    Some(Json::Object(fields)) => fields.get(name)
    _ => None
  }
}

///|
fn assert_facade_string(value : Json?, expected : String) -> Unit raise {
  match value {
    Some(Json::String(actual)) => assert_eq(actual, expected)
    _ => fail("expected JSON string field")
  }
}

///|
fn facade_pair_events() -> Array[@model.Event] raise {
  let key = @model.MessageKey::new(
    trace_id="trace",
    message_id="message",
    attempt=0,
  )
  [
    @model.Event::new(
      event_id="send",
      clock_id="A",
      key~,
      kind=@model.Send,
      timestamp_us=0L,
    ),
    @model.Event::new(
      event_id="receive",
      clock_id="B",
      key~,
      kind=@model.Receive,
      timestamp_us=15L,
    ),
  ]
}

///|
test "JSONL facade parses correlates and reports a feasible analysis" {
  let text =
    #|{"event_id":"send","clock_id":"A","trace_id":"trace","message_id":"message","attempt":0,"kind":"send","ts_us":"0"}
    #|{"event_id":"receive","clock_id":"B","trace_id":"trace","message_id":"message","attempt":0,"kind":"receive","ts_us":"15"}
  let report = @chronolens.analyze_jsonl(text, source_path="facade.jsonl")
  let json = report.to_json()
  assert_facade_string(facade_field(Some(json), "status"), "feasible")
  assert_facade_string(
    facade_field(facade_field(Some(json), "input"), "validation"),
    "valid",
  )
  match facade_field(Some(json), "messages") {
    Some(Json::Array(messages)) => assert_eq(messages.length(), 1)
    _ => fail("expected one correlated message")
  }
}

///|
test "JSONL facade returns parser diagnostics for invalid input" {
  let report = @chronolens.analyze_jsonl("{bad json}")
  let json = report.to_json()
  assert_facade_string(facade_field(Some(json), "status"), "input_invalid")
  assert_facade_string(
    facade_field(facade_field(Some(json), "input"), "validation"),
    "invalid",
  )
}

///|
test "typed-event facade preserves message and prior evidence without parser input" {
  let prior = @constraints.OffsetPrior::new(
    clock_id="B",
    reference_clock="A",
    label="calibration",
    lower_us=10L,
    upper_us=20L,
  )
  let report = @chronolens.analyze_events(facade_pair_events(), priors=[prior])
  let json = report.to_json()
  assert_facade_string(facade_field(Some(json), "status"), "feasible")
  match facade_field(Some(json), "input") {
    Some(Json::Null) => ()
    _ => fail("typed-event analysis must not invent parser input")
  }
  match facade_field(Some(json), "constraints") {
    Some(Json::Array(constraints)) => assert_eq(constraints.length(), 3)
    _ => fail("expected one message and two prior constraints")
  }
  let priors = facade_field(facade_field(Some(json), "model"), "priors")
  match priors {
    Some(Json::Array(values)) => {
      assert_eq(values.length(), 1)
      assert_facade_string(
        facade_field(Some(values[0]), "label"),
        "calibration",
      )
      assert_facade_string(facade_field(Some(values[0]), "lower_us"), "10")
      assert_facade_string(facade_field(Some(values[0]), "upper_us"), "20")
    }
    _ => fail("expected prior in the exported model")
  }
}

///|
test "JSONL facade turns duplicate prior labels into a constraint-build diagnostic" {
  let first = @constraints.OffsetPrior::new(
    clock_id="B",
    reference_clock="A",
    label="duplicate",
    upper_us=20L,
  )
  let second = @constraints.OffsetPrior::new(
    clock_id="C",
    reference_clock="A",
    label="duplicate",
    lower_us=10L,
  )
  let input =
    #|{"event_id":"send","clock_id":"A","trace_id":"trace","message_id":"message","attempt":0,"kind":"send","ts_us":"0"}
  let report = @chronolens.analyze_jsonl(input, priors=[first, second])
  let json = report.to_json()
  assert_facade_string(facade_field(Some(json), "status"), "pipeline_failed")
  assert_facade_string(
    facade_field(facade_field(Some(json), "failure"), "stage"),
    "constraint_build",
  )
  assert_facade_string(
    facade_field(
      facade_field(facade_field(Some(json), "failure"), "error"),
      "code",
    ),
    "duplicate_prior_label",
  )
}
