///|
/// Analyze weak components independently. The requested reference is used in
/// its component; all others use their lexicographically smallest clock.
/// Configuration, graph indexing, partition-budget, and unknown-reference
/// errors fail the call. Per-component computational failures remain explicit.
pub fn analyze_constraints(
  constraints : ArrayView[@model.DifferenceConstraint],
  clock_ids? : ArrayView[String] = [],
  reference_clock? : String,
  limits? : SolveLimits = SolveLimits::default(),
) -> ConstraintAnalysis raise SolveError {
  let graph = index_graph(constraints, clock_ids, limits)
  if reference_clock is Some(requested) {
    if !graph.clocks.contains(requested) {
      raise UnknownReferenceClock(requested)
    }
  }
  let budget = Budget::{ limit: limits.max_edge_visits, used: 0L, passes: 0, }
  let groups = partition_graph(graph, budget)
  let components : Array[ComponentAnalysis] = []
  for component_id, group in groups {
    let mut reference = 0
    if reference_clock is Some(requested) {
      for i, clock in group.clocks {
        if clock == requested {
          reference = i
        }
      }
    }
    let start_visits = budget.used
    let start_passes = budget.passes
    let outcome = try {
      if budget.used >= budget.limit {
        raise EdgeVisitLimitExceeded(budget.limit)
      }
      match solve_graph(group, budget) {
        Feasible(offsets~) =>
          analyze_feasible(group, offsets, reference, budget)
        Infeasible(cycle~) => ComponentInfeasible(cycle~)
      }
    } catch {
      error => ComponentFailed(error~)
    }
    let indices = group.edges.iter().map(edge => edge.index).collect()
    components.push({
      component_id,
      clocks: ReadOnlyArray::from_array(group.clocks),
      reference_clock: group.clocks[reference],
      constraint_indices: ReadOnlyArray::from_array(indices),
      outcome,
      stats: {
        clock_count: group.clocks.length(),
        constraint_count: group.edges.length(),
        passes: budget.passes - start_passes,
        edge_visits: budget.used - start_visits,
      },
    })
  }
  {
    clocks: ReadOnlyArray::from_array(graph.clocks),
    constraints: ReadOnlyArray::from_array(graph.constraints),
    components: ReadOnlyArray::from_array(components),
    stats: {
      clock_count: graph.clocks.length(),
      constraint_count: graph.edges.length(),
      passes: budget.passes,
      edge_visits: budget.used,
    },
  }
}

///|
/// Keep correlation coverage, provenance, tolerance, and assumptions available.
pub fn analyze(
  input : @constraints.ConstraintSet,
  reference_clock? : String,
  limits? : SolveLimits = SolveLimits::default(),
) -> AnalysisReport raise SolveError {
  if input.constraints.length() > limits.max_constraints {
    raise ConstraintLimitExceeded(limits.max_constraints)
  }
  if input.clocks.length() > limits.max_clocks {
    raise ClockLimitExceeded(limits.max_clocks)
  }
  let original = input.constraints.iter().map(edge => edge.constraint).collect()
  let analysis = analyze_constraints(
    original,
    clock_ids=input.clocks,
    reference_clock?,
    limits~,
  )
  { input, analysis, }
}
