///|
fn event(
  id : String,
  kind : @model.EventKind,
  trace? : String = "t",
  message? : String = "m",
  attempt? : Int = 0,
  clock? : String = "A",
  timestamp? : Int64 = 0L,
  line? : Int = 1,
) -> @model.Event raise @model.ModelError {
  let key = @model.MessageKey::new(trace_id=trace, message_id=message, attempt~)
  let source = @model.SourceLocation::new(path="events.jsonl", line~)
  @model.Event::new(
    event_id=id,
    clock_id=clock,
    key~,
    kind~,
    timestamp_us=timestamp,
    source~,
  )
}

///|
test "a unique pair ignores input order and inverted observed timestamps" {
  let send = event("s", @model.Send, clock="A", timestamp=1000000L, line=5)
  let receive = event("r", @model.Receive, clock="B", timestamp=900000L, line=2)
  let report = @correlate.correlate([receive, send])
  assert_true(report.fully_paired())
  assert_eq(report.pairs.length(), 1)
  assert_eq(report.pairs[0].send_event, send)
  assert_eq(report.pairs[0].receive_event, receive)
  assert_eq(report.pairs[0].send_event.source().unwrap().line(), 5)
  assert_eq(report.stats.total_events, 2)
  assert_eq(report.stats.group_count, 1)
}

///|
test "trace identifiers isolate otherwise identical messages" {
  let report = @correlate.correlate([
    event("s", @model.Send, trace="one"),
    event("r", @model.Receive, trace="two"),
  ])
  assert_eq(report.pairs.length(), 0)
  assert_eq(report.unresolved.length(), 2)
  assert_eq(report.stats.missing_groups, 2)
}

///|
test "message identifiers isolate events within one trace" {
  let report = @correlate.correlate([
    event("s", @model.Send, message="request"),
    event("r", @model.Receive, message="response"),
  ])
  assert_eq(report.pairs.length(), 0)
  assert_eq(report.unresolved.length(), 2)
}

///|
test "retry attempts are never paired across attempts" {
  let report = @correlate.correlate([
    event("s0", @model.Send, attempt=0),
    event("r1", @model.Receive, attempt=1),
  ])
  assert_eq(report.pairs.length(), 0)
  assert_eq(report.unresolved[0].key.attempt(), 0)
  assert_eq(report.unresolved[1].key.attempt(), 1)
  assert_true(report.unresolved[0].issues.contains(@correlate.MissingReceive))
  assert_true(report.unresolved[1].issues.contains(@correlate.MissingSend))
}

///|
test "both missing-side diagnostics preserve their evidence" {
  let send = event("s", @model.Send, message="a")
  let receive = event("r", @model.Receive, message="b")
  let report = @correlate.correlate([send, receive])
  assert_true(!report.fully_paired())
  assert_eq(report.unresolved[0].send_events[0], send)
  assert_eq(report.unresolved[0].receive_events.length(), 0)
  assert_eq(report.unresolved[0].issues.length(), 1)
  assert_eq(report.unresolved[0].issues[0], @correlate.MissingReceive)
  assert_eq(report.unresolved[1].receive_events[0], receive)
  assert_eq(report.unresolved[1].issues[0], @correlate.MissingSend)
}

///|
test "multiple sends do not select a best candidate by time" {
  let report = @correlate.correlate([
    event("s2", @model.Send, timestamp=100L),
    event("r", @model.Receive, timestamp=110L),
    event("s1", @model.Send, timestamp=0L),
  ])
  assert_eq(report.pairs.length(), 0)
  assert_eq(report.unresolved.length(), 1)
  assert_eq(report.unresolved[0].issues[0], @correlate.Ambiguous)
  assert_eq(report.unresolved[0].send_events[0].event_id(), "s1")
  assert_eq(report.unresolved[0].send_events[1].event_id(), "s2")
  assert_eq(report.stats.ambiguous_groups, 1)
  assert_eq(report.stats.missing_groups, 0)
}

///|
test "multiple receives and multiple both-side events stay ambiguous" {
  for
    events in [
      [
        event("s", @model.Send),
        event("r1", @model.Receive),
        event("r2", @model.Receive),
      ],
      [
        event("s1", @model.Send),
        event("s2", @model.Send),
        event("r1", @model.Receive),
        event("r2", @model.Receive),
      ],
    ] {
    let report = @correlate.correlate(events)
    assert_eq(report.pairs.length(), 0)
    assert_eq(report.unresolved[0].issues.length(), 1)
    assert_eq(report.unresolved[0].issues[0], @correlate.Ambiguous)
    assert_eq(report.stats.ambiguous_groups, 1)
  }
}

///|
test "a group can have both a missing side and ambiguity" {
  let report = @correlate.correlate([
    event("s2", @model.Send),
    event("s1", @model.Send),
  ])
  assert_eq(report.unresolved[0].issues.length(), 2)
  assert_eq(report.unresolved[0].issues[0], @correlate.MissingReceive)
  assert_eq(report.unresolved[0].issues[1], @correlate.Ambiguous)
  assert_eq(report.stats.unresolved_groups, 1)
  assert_eq(report.stats.missing_groups, 1)
  assert_eq(report.stats.ambiguous_groups, 1)
}

///|
test "mixed groups preserve every event exactly once without inventing pairs" {
  let events = [
    event("a-send", @model.Send, message="a"),
    event("b-send", @model.Send, message="b"),
    event("a-recv", @model.Receive, message="a"),
    event("c-send-2", @model.Send, message="c"),
    event("c-recv", @model.Receive, message="c"),
    event("c-send-1", @model.Send, message="c"),
  ]
  let report = @correlate.correlate(events)
  assert_eq(report.stats.total_events, 6)
  assert_eq(report.stats.group_count, 3)
  assert_eq(report.stats.paired_groups, 1)
  assert_eq(report.stats.unresolved_groups, 2)
  assert_eq(report.stats.missing_groups, 1)
  assert_eq(report.stats.ambiguous_groups, 1)
  let seen : Map[String, Unit] = Map([])
  for pair in report.pairs {
    assert_true(!seen.contains(pair.send_event.event_id()))
    seen[pair.send_event.event_id()] = ()
    assert_true(!seen.contains(pair.receive_event.event_id()))
    seen[pair.receive_event.event_id()] = ()
  }
  for group in report.unresolved {
    for event in group.send_events {
      assert_true(!seen.contains(event.event_id()))
      seen[event.event_id()] = ()
    }
    for event in group.receive_events {
      assert_true(!seen.contains(event.event_id()))
      seen[event.event_id()] = ()
    }
  }
  assert_eq(seen.length(), events.length())
}

///|
test "results are deterministic across permutations and do not mutate input" {
  let a = event("z", @model.Send, message="b", attempt=2147483647)
  let b = event("y", @model.Receive, message="b", attempt=2147483647)
  let c = event("x", @model.Send, message="b", attempt=0)
  let d = event("w", @model.Send, message="a")
  let e = event("v", @model.Send, message="a")
  let f = event("u", @model.Receive, message="a")
  let expected = @correlate.correlate([a, b, c, d, e, f])
  for events in [[f, e, d, c, b, a], [b, e, a, f, c, d]] {
    let before = events.map(e => e.event_id())
    assert_eq(@correlate.correlate(events), expected)
    assert_eq(events.map(e => e.event_id()), before)
  }
  assert_eq(expected.unresolved[0].key.message_id(), "a")
  assert_eq(expected.unresolved[1].key.attempt(), 0)
}

///|
test "full message keys avoid separator-concatenation collisions" {
  let report = @correlate.correlate([
    event("s", @model.Send, trace="a|b", message="c"),
    event("r", @model.Receive, trace="a", message="b|c"),
  ])
  assert_eq(report.stats.group_count, 2)
  assert_eq(report.pairs.length(), 0)
}

///|
test "duplicate event ids reject the entire collection even across keys" {
  for
    events in [
      [event("same", @model.Send), event("same", @model.Send)],
      [event("same", @model.Send), event("same", @model.Receive, trace="other")],
    ] {
    try @correlate.correlate(events) catch {
      err => assert_eq(err, @correlate.DuplicateEventId("same"))
    } noraise {
      _ => fail("expected duplicate event rejection")
    }
  }
}

///|
test "event cap accepts exact boundary and rejects excess" {
  let events = [event("s", @model.Send), event("r", @model.Receive)]
  assert_true(@correlate.correlate(events, max_events=2).fully_paired())
  try @correlate.correlate(events, max_events=1) catch {
    err => assert_eq(err, @correlate.EventLimitExceeded(limit=1, count=2))
  } noraise {
    _ => fail("expected event limit rejection")
  }
  for limit in [0, -1, 1000001] {
    try @correlate.correlate(events, max_events=limit) catch {
      err => assert_eq(err, @correlate.InvalidEventLimit)
    } noraise {
      _ => fail("expected invalid limit rejection")
    }
  }
}

///|
test "empty typed collections have explicitly zero coverage" {
  let report = @correlate.correlate([])
  assert_true(report.fully_paired())
  assert_eq(report.stats.total_events, 0)
  assert_eq(report.stats.group_count, 0)
  assert_eq(report.pairs.length(), 0)
  assert_eq(report.unresolved.length(), 0)
}

///|
test "same-clock and extreme timestamps do not change pairing semantics" {
  let send = event(
    "s",
    @model.Send,
    message="消息",
    timestamp=9223372036854775807L,
  )
  let receive = event(
    "r",
    @model.Receive,
    message="消息",
    timestamp=-9223372036854775807L - 1L,
  )
  let report = @correlate.correlate([send, receive])
  assert_true(report.fully_paired())
  assert_eq(report.pairs[0].send_event.timestamp_us(), 9223372036854775807L)
  assert_eq(
    report.pairs[0].receive_event.timestamp_us(),
    -9223372036854775807L - 1L,
  )
}
