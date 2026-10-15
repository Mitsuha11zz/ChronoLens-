///|
priv struct IndexedEdge {
  from : Int
  to : Int
  index : Int
  weight : Int64
}

///|
priv struct Graph {
  clocks : Array[String]
  constraints : Array[@model.DifferenceConstraint]
  edges : Array[IndexedEdge]
}

///|
fn add_clock(
  clock : String,
  names : Map[String, Unit],
  limit : Int,
) -> Unit raise SolveError {
  if clock.trim().is_empty() {
    raise EmptyClockId
  }
  if !names.contains(clock) {
    if names.length() >= limit {
      raise ClockLimitExceeded(limit)
    }
    names[clock] = ()
  }
}

///|
fn index_graph(
  constraints : ArrayView[@model.DifferenceConstraint],
  clock_ids : ArrayView[String],
  limits : SolveLimits,
) -> Graph raise SolveError {
  if constraints.length() > limits.max_constraints {
    raise ConstraintLimitExceeded(limits.max_constraints)
  }
  // Explicit clock IDs represent a set; bound the list before traversing it.
  if clock_ids.length() > limits.max_clocks {
    raise ClockLimitExceeded(limits.max_clocks)
  }
  let names : Map[String, Unit] = Map([])
  for clock in clock_ids {
    add_clock(clock, names, limits.max_clocks)
  }
  for constraint in constraints {
    add_clock(constraint.edge_from(), names, limits.max_clocks)
    add_clock(constraint.edge_to(), names, limits.max_clocks)
  }
  let clocks = Array::from_iter(names.keys())
  clocks.sort_by((a, b) => a.compare(b))
  let indices : Map[String, Int] = Map([])
  for i, clock in clocks {
    indices[clock] = i
  }
  let original = Array::from_iter(constraints.iter())
  let edges : Array[IndexedEdge] = []
  for i, constraint in original {
    edges.push({
      from: indices[constraint.edge_from()],
      to: indices[constraint.edge_to()],
      index: i,
      weight: constraint.upper_bound_us(),
    })
  }
  { clocks, constraints: original, edges, }
}

///|
fn checked_add(
  a : Int64,
  b : Int64,
  phase : SolvePhase,
  index : Int,
) -> Int64 raise SolveError {
  if (b > 0L && a > @int64.MAX_VALUE - b) ||
    (b < 0L && a < @int64.MIN_VALUE - b) {
    raise ArithmeticOverflow(phase~, constraint_index=index)
  }
  a + b
}
