///|
fn sorted_events(events : ArrayView[@model.Event]) -> Array[@model.Event] {
  let sorted = Array::from_iter(events.iter())
  sorted.sort_by((a, b) => a.event_id().lexical_compare(b.event_id()))
  sorted
}

///|
fn analysis_events(report : @solver.AnalysisReport) -> Array[@model.Event] {
  let events : Array[@model.Event] = []
  for pair in report.input.correlation.pairs {
    events.push(pair.send_event)
    events.push(pair.receive_event)
  }
  for group in report.input.correlation.unresolved {
    for event in group.send_events {
      events.push(event)
    }
    for event in group.receive_events {
      events.push(event)
    }
  }
  sorted_events(events)
}

///|
fn string_array(values : ArrayView[String]) -> Json {
  Json::array(values.iter().map(Json::string).collect())
}

///|
fn index_array(values : ArrayView[Int32]) -> Json {
  Json::array(values.iter().map(value => Json(value)).collect())
}

///|
fn optional_i64(value : Int64?) -> Json {
  match value {
    Some(value) => Json::string(value.to_string())
    None => Json::null()
  }
}

///|
fn event_json(event : @model.Event) -> Json {
  Json::object({
    "event_id": Json::string(event.event_id()),
    "clock_id": Json::string(event.clock_id()),
    "trace_id": Json::string(event.key().trace_id()),
    "message_id": Json::string(event.key().message_id()),
    "attempt": Json(event.key().attempt()),
    "kind": Json::string(
      match event.kind() {
        @model.Send => "send"
        @model.Receive => "receive"
      },
    ),
    "ts_us": Json::string(event.timestamp_us().to_string()),
    "source": match event.source() {
      None => Json::null()
      Some(source) =>
        Json::object({
          "path": Json::string(source.path()),
          "line": Json(source.line()),
        })
    },
  })
}

///|
fn key_json(key : @model.MessageKey) -> Json {
  Json::object({
    "trace_id": Json::string(key.trace_id()),
    "message_id": Json::string(key.message_id()),
    "attempt": Json(key.attempt()),
  })
}

///|
fn origin_json(origin : @model.ConstraintOrigin) -> Json {
  match origin {
    @model.Message(send_event_id~, receive_event_id~) =>
      Json::object({
        "kind": Json::string("message"),
        "send_event_id": Json::string(send_event_id),
        "receive_event_id": Json::string(receive_event_id),
      })
    @model.Prior(label~) =>
      Json::object({
        "kind": Json::string("prior"),
        "label": Json::string(label),
      })
  }
}

///|
fn prior_json(prior : @constraints.OffsetPrior) -> Json {
  Json::object({
    "label": Json::string(prior.label),
    "clock_id": Json::string(prior.clock_id),
    "reference_clock": Json::string(prior.reference_clock),
    "lower_us": optional_i64(prior.lower_us),
    "upper_us": optional_i64(prior.upper_us),
  })
}
