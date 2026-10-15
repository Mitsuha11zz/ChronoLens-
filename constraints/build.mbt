///|
fn checked_add(
  a : Int64,
  b : Int64,
  origin : @model.ConstraintOrigin,
) -> Int64 raise ConstraintBuildError {
  if (b > 0L && a > @int64.MAX_VALUE - b) ||
    (b < 0L && a < @int64.MIN_VALUE - b) {
    raise ArithmeticOverflow(origin)
  }
  a + b
}

///|
fn checked_sub(
  a : Int64,
  b : Int64,
  origin : @model.ConstraintOrigin,
) -> Int64 raise ConstraintBuildError {
  if (b > 0L && a < @int64.MIN_VALUE + b) ||
    (b < 0L && a > @int64.MAX_VALUE + b) {
    raise ArithmeticOverflow(origin)
  }
  a - b
}

///|
/// Reorder r - s + tolerance so a representable final value is not rejected
/// because of an avoidable intermediate overflow. Tolerance is nonnegative.
fn message_bound(
  receive : Int64,
  send : Int64,
  tolerance : Int64,
  origin : @model.ConstraintOrigin,
) -> Int64 raise ConstraintBuildError {
  if send >= 0L {
    checked_add(receive, tolerance - send, origin)
  } else {
    checked_add(checked_sub(receive, send, origin), tolerance, origin)
  }
}

///|
fn make_edge(
  left : String,
  right : String,
  bound : Int64,
  origin : @model.ConstraintOrigin,
  evidence : ConstraintEvidence,
) -> BuiltConstraint raise ConstraintBuildError {
  let constraint = @model.DifferenceConstraint::new(
    left_clock=left,
    right_clock=right,
    upper_bound_us=bound,
    origin~,
  ) catch {
    @model.ModelError::EmptyIdentifier(field) => raise InvalidPriorField(field)
    _ => raise InvalidPriorField("constraint")
  }
  { constraint, evidence, }
}

///|
/// Convert unique message pairs using s + o_send <= r + o_receive + tolerance.
/// Missing and ambiguous groups remain in correlation; their clocks remain in
/// clocks. Priors may introduce clocks. Ordering follows sorted message keys,
/// then prior labels; lower-bound edges precede upper-bound edges.
pub fn build(
  correlation : @correlate.CorrelationReport,
  relation_tolerance_us? : Int64 = 0L,
  priors? : ArrayView[OffsetPrior] = [],
  max_constraints? : Int = 20000,
) -> ConstraintSet raise ConstraintBuildError {
  if relation_tolerance_us < 0L {
    raise InvalidTolerance
  }
  if max_constraints <= 0 || max_constraints > 2000000 {
    raise InvalidConstraintLimit
  }
  let mut count = correlation.pairs.length()
  if count > max_constraints {
    raise ConstraintLimitExceeded(max_constraints)
  }
  let labels : Map[String, Bool] = Map([])
  for prior in priors {
    if labels.contains(prior.label) {
      raise DuplicatePriorLabel(prior.label)
    }
    labels[prior.label] = true
    if prior.lower_us is Some(_) {
      count += 1
    }
    if prior.upper_us is Some(_) {
      count += 1
    }
    if count > max_constraints {
      raise ConstraintLimitExceeded(max_constraints)
    }
  }
  let clocks : Map[String, Bool] = Map([])
  let edges : Array[BuiltConstraint] = []
  for pair in correlation.pairs {
    let send = pair.send_event
    let receive = pair.receive_event
    clocks[send.clock_id()] = true
    clocks[receive.clock_id()] = true
    let origin = @model.ConstraintOrigin::Message(
      send_event_id=send.event_id(),
      receive_event_id=receive.event_id(),
    )
    let bound = message_bound(
      receive.timestamp_us(),
      send.timestamp_us(),
      relation_tolerance_us,
      origin,
    )
    edges.push(
      make_edge(
        send.clock_id(),
        receive.clock_id(),
        bound,
        origin,
        Message(pair~, tolerance_us=relation_tolerance_us),
      ),
    )
  }
  for group in correlation.unresolved {
    for event in group.send_events {
      clocks[event.clock_id()] = true
    }
    for event in group.receive_events {
      clocks[event.clock_id()] = true
    }
  }
  let sorted_priors = Array::from_iter(priors.iter())
  sorted_priors.sort_by(fn(a, b) { a.label.compare(b.label) })
  for prior in sorted_priors {
    clocks[prior.clock_id] = true
    clocks[prior.reference_clock] = true
    let origin = @model.ConstraintOrigin::Prior(label=prior.label)
    if prior.lower_us is Some(lower) {
      let bound = checked_sub(0L, lower, origin)
      edges.push(
        make_edge(
          prior.reference_clock,
          prior.clock_id,
          bound,
          origin,
          Prior(prior~, lower_bound=true),
        ),
      )
    }
    if prior.upper_us is Some(upper) {
      edges.push(
        make_edge(
          prior.clock_id,
          prior.reference_clock,
          upper,
          origin,
          Prior(prior~, lower_bound=false),
        ),
      )
    }
  }
  let sorted_clocks = Array::from_iter(clocks.keys())
  sorted_clocks.sort_by(fn(a, b) { a.compare(b) })
  {
    clocks: ReadOnlyArray::from_array(sorted_clocks),
    constraints: ReadOnlyArray::from_array(edges),
    correlation,
    relation_tolerance_us,
  }
}
