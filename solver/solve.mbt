///|
/// Direct graph entry point. Additional clock_ids preserve isolated clocks.
/// Empty constraints are feasible with zero offsets; this is zero evidence.
/// Input edge order determines deterministic relaxation and witness selection.
pub fn solve_constraints(
  constraints : ArrayView[@model.DifferenceConstraint],
  clock_ids? : ArrayView[String] = [],
  limits? : SolveLimits = SolveLimits::default(),
) -> ConstraintSolution raise SolveError {
  let graph = index_graph(constraints, clock_ids, limits)
  let budget = Budget::{ limit: limits.max_edge_visits, used: 0L, passes: 0, }
  let outcome = solve_graph(graph, budget)
  {
    clocks: ReadOnlyArray::from_array(graph.clocks),
    constraints: ReadOnlyArray::from_array(graph.constraints),
    outcome,
    stats: {
      clock_count: graph.clocks.length(),
      constraint_count: graph.edges.length(),
      passes: budget.passes,
      edge_visits: budget.used,
    },
  }
}

///|
fn solve_graph(graph : Graph, budget : Budget) -> Feasibility raise SolveError {
  let count = graph.clocks.length()
  let distances = Array::make(count, 0L)
  let predecessors = Array::make(count, -1)
  let mut cycle_node = -1
  // Zero initialization is an implicit super-source covering every component.
  for pass = 0; pass < count; pass = pass + 1 {
    if graph.edges.is_empty() {
      break
    }
    let mut updated_node = -1
    for position, edge in graph.edges {
      budget.visit()
      // A negative self-loop is already a complete witness; repeated
      // relaxation could otherwise underflow before the V-th pass.
      if edge.from == edge.to && edge.weight < 0L {
        predecessors[edge.to] = position
        cycle_node = edge.to
        break
      }
      let candidate = checked_add(
        distances[edge.from],
        edge.weight,
        Relaxation,
        edge.index,
      )
      if candidate < distances[edge.to] {
        distances[edge.to] = candidate
        predecessors[edge.to] = position
        updated_node = edge.to
      }
    }
    budget.passes += 1
    if cycle_node >= 0 {
      break
    }
    if updated_node < 0 {
      break
    }
    if pass == count - 1 {
      cycle_node = updated_node
    }
  }
  if cycle_node >= 0 {
    Infeasible(cycle=extract_cycle(cycle_node, predecessors, graph, budget))
  } else {
    verify_offsets(distances, graph, budget)
    let offsets : Array[ClockOffset] = []
    for i, clock_id in graph.clocks {
      offsets.push({ clock_id, offset_us: distances[i], })
    }
    Feasible(offsets=ReadOnlyArray::from_array(offsets))
  }
}

///|
/// Preserve the entire build report so witness indices resolve to original
/// message pairs, source locations, tolerance, and prior bounds.
pub fn solve(
  input : @constraints.ConstraintSet,
  limits? : SolveLimits = SolveLimits::default(),
) -> SolveReport raise SolveError {
  // Check before copying the constraint projection.
  if input.constraints.length() > limits.max_constraints {
    raise ConstraintLimitExceeded(limits.max_constraints)
  }
  if input.clocks.length() > limits.max_clocks {
    raise ClockLimitExceeded(limits.max_clocks)
  }
  let original = input.constraints.iter().map(edge => edge.constraint).collect()
  let solution = solve_constraints(original, clock_ids=input.clocks, limits~)
  { input, solution, }
}
