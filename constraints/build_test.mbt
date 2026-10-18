///|
fn pair(
  send : Int64,
  receive : Int64,
  same_clock? : Bool = false,
) -> @correlate.CorrelationReport raise {
  let key = @model.MessageKey::new(trace_id="t", message_id="m", attempt=0)
  let source = @model.SourceLocation::new(path="events.jsonl", line=7)
  @correlate.correlate([
    @model.Event::new(
      event_id="s",
      clock_id="A",
      key~,
      kind=@model.Send,
      timestamp_us=send,
      source~,
    ),
    @model.Event::new(
      event_id="r",
      clock_id=if same_clock { "A" } else { "B" },
      key~,
      kind=@model.Receive,
      timestamp_us=receive,
    ),
  ])
}

///|
fn empty_pairs() -> @correlate.CorrelationReport raise {
  @correlate.correlate([])
}

///|
fn build_error(
  action : () -> @constraints.ConstraintSet raise @constraints.ConstraintBuildError,
) -> @constraints.ConstraintBuildError raise {
  try action() catch {
    error => error
  } noraise {
    _ => fail("expected build error")
  }
}

///|
test "message direction tolerance and complete provenance" {
  let paired = pair(1000000L, 900000L)
  let built = @constraints.build(paired, relation_tolerance_us=25L)
  let edge = built.constraints[0]
  assert_eq(edge.constraint.left_clock(), "A")
  assert_eq(edge.constraint.right_clock(), "B")
  assert_eq(edge.constraint.edge_from(), "B")
  assert_eq(edge.constraint.edge_to(), "A")
  assert_eq(edge.constraint.upper_bound_us(), -99975L)
  assert_eq(
    edge.constraint.origin(),
    @model.Message(send_event_id="s", receive_event_id="r"),
  )
  match edge.evidence {
    @constraints.Message(pair~, tolerance_us~) => {
      assert_eq(pair, paired.pairs[0])
      assert_eq(tolerance_us, 25L)
      assert_eq(pair.send_event.source().unwrap().path(), "events.jsonl")
      assert_eq(pair.send_event.source().unwrap().line(), 7)
    }
    _ => fail("expected message evidence")
  }
  assert_eq(built.correlation, paired)
}

///|
test "negative self-loop is preserved for solving" {
  let built = @constraints.build(pair(10L, 0L, same_clock=true))
  assert_eq(built.clocks.length(), 1)
  assert_eq(built.constraints[0].constraint.upper_bound_us(), -10L)
  assert_eq(built.constraints[0].constraint.edge_from(), "A")
  assert_eq(built.constraints[0].constraint.edge_to(), "A")
}

///|
test "empty correlation produces a zero-coverage graph" {
  let built = @constraints.build(empty_pairs())
  assert_eq(built.clocks.length(), 0)
  assert_eq(built.constraints.length(), 0)
  assert_eq(built.correlation.stats.total_events, 0)
}

///|
test "negative tolerance is rejected" {
  let paired = pair(0L, 0L)
  assert_eq(
    build_error(() => @constraints.build(paired, relation_tolerance_us=-1L)),
    @constraints.InvalidTolerance,
  )
}

///|
test "prior bounds have opposite orientations and explicit evidence" {
  let prior = @constraints.OffsetPrior::new(
    clock_id="B",
    reference_clock="A",
    label="calibration",
    lower_us=100L,
    upper_us=160L,
  )
  let built = @constraints.build(empty_pairs(), priors=[prior])
  assert_eq(Array::from_iter(built.clocks.iter()), ["A", "B"])
  assert_eq(built.constraints.length(), 2)
  assert_eq(built.constraints[0].constraint.left_clock(), "A")
  assert_eq(built.constraints[0].constraint.right_clock(), "B")
  assert_eq(built.constraints[0].constraint.upper_bound_us(), -100L)
  assert_eq(built.constraints[1].constraint.left_clock(), "B")
  assert_eq(built.constraints[1].constraint.upper_bound_us(), 160L)
  assert_eq(
    built.constraints[0].evidence,
    @constraints.Prior(prior~, lower_bound=true),
  )
  assert_eq(
    built.constraints[1].evidence,
    @constraints.Prior(prior~, lower_bound=false),
  )
}

///|
test "single-sided priors and deterministic label order" {
  let low = @constraints.OffsetPrior::new(
    clock_id="C",
    reference_clock="A",
    label="z",
    lower_us=-3L,
  )
  let high = @constraints.OffsetPrior::new(
    clock_id="B",
    reference_clock="A",
    label="a",
    upper_us=-1L,
  )
  let empty = empty_pairs()
  let forward = @constraints.build(empty, priors=[low, high])
  assert_eq(forward, @constraints.build(empty, priors=[high, low]))
  assert_eq(forward.constraints[0].constraint.origin(), @model.Prior(label="a"))
  assert_eq(forward.constraints[1].constraint.upper_bound_us(), 3L)
}

///|
test "invalid prior identifiers bounds and ordering are rejected" {
  for
    (clock, reference, label) in [
      ("", "A", "p"),
      ("B", " ", "p"),
      ("B", "A", " "),
    ] {
    try
      @constraints.OffsetPrior::new(
        clock_id=clock,
        reference_clock=reference,
        label~,
        upper_us=0L,
      )
    catch {
      @constraints.InvalidPriorField(_) => ()
      _ => fail("expected identifier error")
    } noraise {
      _ => fail("expected prior rejection")
    }
  }
  try
    @constraints.OffsetPrior::new(
      clock_id="B",
      reference_clock="A",
      label="empty",
    )
  catch {
    error => assert_eq(error, @constraints.EmptyPriorBounds("empty"))
  } noraise {
    _ => fail("expected empty bounds rejection")
  }
  try
    @constraints.OffsetPrior::new(
      clock_id="B",
      reference_clock="A",
      label="inverted",
      lower_us=2L,
      upper_us=1L,
    )
  catch {
    error => assert_eq(error, @constraints.InvertedPriorRange("inverted"))
  } noraise {
    _ => fail("expected inverted bounds rejection")
  }
}

///|
test "duplicate prior labels are rejected atomically" {
  let a = @constraints.OffsetPrior::new(
    clock_id="A",
    reference_clock="B",
    label="same",
    upper_us=1L,
  )
  let b = @constraints.OffsetPrior::new(
    clock_id="C",
    reference_clock="B",
    label="same",
    lower_us=0L,
  )
  let empty = empty_pairs()
  assert_eq(
    build_error(() => @constraints.build(empty, priors=[a, b])),
    @constraints.DuplicatePriorLabel("same"),
  )
}

///|
test "minimum prior lower bound reports negation overflow" {
  let prior = @constraints.OffsetPrior::new(
    clock_id="A",
    reference_clock="B",
    label="min",
    lower_us=@int64.MIN_VALUE,
  )
  let empty = empty_pairs()
  assert_eq(
    build_error(() => @constraints.build(empty, priors=[prior])),
    @constraints.ArithmeticOverflow(@model.Prior(label="min")),
  )
}

///|
test "minimum and maximum upper prior bounds remain exact" {
  for upper in [@int64.MIN_VALUE, @int64.MAX_VALUE] {
    let prior = @constraints.OffsetPrior::new(
      clock_id="A",
      reference_clock="B",
      label="edge",
      upper_us=upper,
    )
    let result = @constraints.build(empty_pairs(), priors=[prior])
    assert_eq(result.constraints[0].constraint.upper_bound_us(), upper)
  }
}

///|
test "constraint caps validate settings and count both prior edges" {
  let empty = empty_pairs()
  for cap in [0, -1, 2000001] {
    assert_eq(
      build_error(() => @constraints.build(empty, max_constraints=cap)),
      @constraints.InvalidConstraintLimit,
    )
  }
  let prior = @constraints.OffsetPrior::new(
    clock_id="A",
    reference_clock="B",
    label="p",
    lower_us=0L,
    upper_us=1L,
  )
  assert_eq(
    build_error(() => {
      @constraints.build(empty, priors=[prior], max_constraints=1)
    }),
    @constraints.ConstraintLimitExceeded(1),
  )
  assert_eq(
    @constraints.build(empty, priors=[prior], max_constraints=2).constraints.length(),
    2,
  )
}

///|
test "arithmetic agrees with bigint on 405 full-range combinations" {
  let values = [
    @int64.MIN_VALUE,
    @int64.MIN_VALUE + 1L,
    -100L,
    -1L,
    0L,
    1L,
    100L,
    @int64.MAX_VALUE - 1L,
    @int64.MAX_VALUE,
  ]
  let tolerances = [0L, 1L, 100L, @int64.MAX_VALUE - 1L, @int64.MAX_VALUE]
  for send in values {
    for receive in values {
      let paired = pair(send, receive)
      for tolerance in tolerances {
        let exact = @bigint.BigInt::from_int64(receive) -
          @bigint.BigInt::from_int64(send) +
          @bigint.BigInt::from_int64(tolerance)
        let fits = exact.compare_int64(@int64.MIN_VALUE) >= 0 &&
          exact.compare_int64(@int64.MAX_VALUE) <= 0
        try @constraints.build(paired, relation_tolerance_us=tolerance) catch {
          error => {
            assert_true(!fits)
            assert_eq(
              error,
              @constraints.ArithmeticOverflow(
                @model.Message(send_event_id="s", receive_event_id="r"),
              ),
            )
          }
        } noraise {
          result => {
            assert_true(fits)
            assert_eq(
              result.constraints[0].constraint.upper_bound_us(),
              exact.to_int64(),
            )
          }
        }
      }
    }
  }
}
