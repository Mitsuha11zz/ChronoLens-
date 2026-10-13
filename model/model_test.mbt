///|
test "message keys isolate retries and traces and work as map keys" {
  let first = @model.MessageKey::new(trace_id="t1", message_id="m", attempt=0)
  let same = @model.MessageKey::new(trace_id="t1", message_id="m", attempt=0)
  let retry = @model.MessageKey::new(trace_id="t1", message_id="m", attempt=1)
  let other = @model.MessageKey::new(trace_id="t2", message_id="m", attempt=0)
  assert_eq(first, same)
  assert_true(first != retry)
  assert_true(first != other)
  let keys : Map[@model.MessageKey, Int] = Map([])
  keys[first] = 1
  keys[retry] = 2
  keys[other] = 3
  assert_eq(keys.length(), 3)
  assert_eq(keys[same], 1)
  assert_eq(first.trace_id(), "t1")
  assert_eq(first.message_id(), "m")
  assert_eq(retry.attempt(), 1)
}

///|
test "message key rejects blank identifiers and negative retries" {
  try
    @model.MessageKey::new(trace_id=" \t\n", message_id="m", attempt=0)
  catch {
    err => assert_eq(err, @model.EmptyIdentifier("trace_id"))
  } noraise {
    _ => fail("expected blank trace identifier error")
  }
  try @model.MessageKey::new(trace_id="t", message_id="", attempt=0) catch {
    err => assert_eq(err, @model.EmptyIdentifier("message_id"))
  } noraise {
    _ => fail("expected empty message identifier error")
  }
  try @model.MessageKey::new(trace_id="t", message_id="m", attempt=-1) catch {
    err => assert_eq(err, @model.InvalidAttempt(-1))
  } noraise {
    _ => fail("expected negative retry error")
  }
}

///|
test "identifiers are preserved including unicode and surrounding spaces" {
  let key = @model.MessageKey::new(
    trace_id="调用-1",
    message_id=" 消息 ",
    attempt=0,
  )
  let event = @model.Event::new(
    event_id=" 事件-1 ",
    clock_id="节点-B",
    key~,
    kind=@model.Send,
    timestamp_us=0L,
  )
  assert_eq(event.event_id(), " 事件-1 ")
  assert_eq(event.clock_id(), "节点-B")
  assert_eq(event.key().message_id(), " 消息 ")
}

///|
test "events preserve signed 64-bit microseconds and evidence" {
  let key = @model.MessageKey::new(trace_id="t", message_id="m", attempt=0)
  let source = @model.SourceLocation::new(path="日志.jsonl", line=1)
  let event = @model.Event::new(
    event_id="e",
    clock_id="A",
    key~,
    kind=@model.Receive,
    timestamp_us=9223372036854775807L,
    source~,
  )
  assert_eq(event.timestamp_us(), 9223372036854775807L)
  assert_eq(event.kind(), @model.Receive)
  assert_eq(event.source(), Some(source))
  assert_eq(source.path(), "日志.jsonl")
  assert_eq(source.line(), 1)
  let negative = @model.Event::new(
    event_id="e2",
    clock_id="A",
    key~,
    kind=@model.Send,
    timestamp_us=-9223372036854775807L - 1L,
  )
  assert_eq(negative.timestamp_us(), -9223372036854775807L - 1L)
  assert_eq(negative.source(), None)
}

///|
test "events reject missing event and clock identities" {
  let key = @model.MessageKey::new(trace_id="t", message_id="m", attempt=0)
  try
    @model.Event::new(
      event_id="",
      clock_id="A",
      key~,
      kind=@model.Send,
      timestamp_us=0L,
    )
  catch {
    err => assert_eq(err, @model.EmptyIdentifier("event_id"))
  } noraise {
    _ => fail("expected missing event identifier error")
  }
  try
    @model.Event::new(
      event_id="e",
      clock_id=" \t",
      key~,
      kind=@model.Send,
      timestamp_us=0L,
    )
  catch {
    err => assert_eq(err, @model.EmptyIdentifier("clock_id"))
  } noraise {
    _ => fail("expected missing clock identifier error")
  }
}

///|
test "evidence locations require a path and a one-based line" {
  try @model.SourceLocation::new(path="", line=1) catch {
    err => assert_eq(err, @model.EmptyIdentifier("source.path"))
  } noraise {
    _ => fail("expected missing path error")
  }
  for line in [0, -1] {
    try @model.SourceLocation::new(path="events.jsonl", line~) catch {
      err => assert_eq(err, @model.InvalidSourceLine(line))
    } noraise {
      _ => fail("expected invalid source line error")
    }
  }
}

///|
test "difference constraint fixes edge orientation and preserves evidence" {
  let origin = @model.Message(send_event_id="a1", receive_event_id="b1")
  let constraint = @model.DifferenceConstraint::new(
    left_clock="A",
    right_clock="B",
    upper_bound_us=-100000L,
    origin~,
  )
  assert_eq(constraint.left_clock(), "A")
  assert_eq(constraint.right_clock(), "B")
  assert_eq(constraint.edge_from(), "B")
  assert_eq(constraint.edge_to(), "A")
  assert_eq(constraint.upper_bound_us(), -100000L)
  assert_eq(constraint.origin(), origin)
}

///|
test "self constraints and full-width bounds remain available to the solver" {
  let constraint = @model.DifferenceConstraint::new(
    left_clock="A",
    right_clock="A",
    upper_bound_us=-1L,
    origin=@model.Prior(label="self-conflict"),
  )
  assert_eq(constraint.edge_from(), constraint.edge_to())
  assert_eq(constraint.upper_bound_us(), -1L)
  for bound in [-9223372036854775807L - 1L, 0L, 9223372036854775807L] {
    let c = @model.DifferenceConstraint::new(
      left_clock="A",
      right_clock="B",
      upper_bound_us=bound,
      origin=@model.Prior(label="range"),
    )
    assert_eq(c.upper_bound_us(), bound)
  }
}

///|
test "constraints reject invalid clocks and evidence references" {
  try
    @model.DifferenceConstraint::new(
      left_clock="",
      right_clock="B",
      upper_bound_us=0L,
      origin=@model.Prior(label="p"),
    )
  catch {
    err => assert_eq(err, @model.EmptyIdentifier("left_clock"))
  } noraise {
    _ => fail("expected missing left clock error")
  }
  try
    @model.DifferenceConstraint::new(
      left_clock="A",
      right_clock="",
      upper_bound_us=0L,
      origin=@model.Prior(label="p"),
    )
  catch {
    err => assert_eq(err, @model.EmptyIdentifier("right_clock"))
  } noraise {
    _ => fail("expected missing right clock error")
  }
  try
    @model.DifferenceConstraint::new(
      left_clock="A",
      right_clock="B",
      upper_bound_us=0L,
      origin=@model.Message(send_event_id="", receive_event_id="b1"),
    )
  catch {
    err => assert_eq(err, @model.EmptyIdentifier("origin.send_event_id"))
  } noraise {
    _ => fail("expected missing send event error")
  }
  try
    @model.DifferenceConstraint::new(
      left_clock="A",
      right_clock="B",
      upper_bound_us=0L,
      origin=@model.Message(send_event_id="a1", receive_event_id=" "),
    )
  catch {
    err => assert_eq(err, @model.EmptyIdentifier("origin.receive_event_id"))
  } noraise {
    _ => fail("expected missing receive event error")
  }
  try
    @model.DifferenceConstraint::new(
      left_clock="A",
      right_clock="B",
      upper_bound_us=0L,
      origin=@model.Prior(label=" "),
    )
  catch {
    err => assert_eq(err, @model.EmptyIdentifier("origin.label"))
  } noraise {
    _ => fail("expected missing prior label error")
  }
}
