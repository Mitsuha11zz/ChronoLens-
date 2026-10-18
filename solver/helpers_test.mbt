///|
fn edge(
  from : String,
  to : String,
  weight : Int64,
  label? : String = "edge",
) -> @model.DifferenceConstraint raise {
  @model.DifferenceConstraint::new(
    left_clock=to,
    right_clock=from,
    upper_bound_us=weight,
    origin=@model.Prior(label~),
  )
}

///|
fn solution_error(
  action : () -> @solver.ConstraintSolution raise @solver.SolveError,
) -> @solver.SolveError raise {
  try action() catch {
    error => error
  } noraise {
    _ => fail("expected solver error")
  }
}

///|
fn analysis_error(
  action : () -> @solver.ConstraintAnalysis raise @solver.SolveError,
) -> @solver.SolveError raise {
  try action() catch {
    error => error
  } noraise {
    _ => fail("expected analysis error")
  }
}

///|
/// Independent arbitrary-precision check of every original inequality.
fn verify_assignment(
  constraints : ArrayView[@model.DifferenceConstraint],
  offsets : ReadOnlyArray[@solver.ClockOffset],
) -> Unit raise {
  let values : Map[String, Int64] = Map([])
  for offset in offsets {
    assert_true(!values.contains(offset.clock_id))
    values[offset.clock_id] = offset.offset_us
  }
  for constraint in constraints {
    assert_true(values.contains(constraint.left_clock()))
    assert_true(values.contains(constraint.right_clock()))
    let difference = @bigint.BigInt::from_int64(values[constraint.left_clock()]) -
      @bigint.BigInt::from_int64(values[constraint.right_clock()])
    assert_true(difference.compare_int64(constraint.upper_bound_us()) <= 0)
  }
}

///|
/// Independent check of global indices, exact constraints, closure, and weight.
fn verify_cycle(
  constraints : ArrayView[@model.DifferenceConstraint],
  cycle : @solver.NegativeCycle,
) -> Unit raise {
  assert_true(!cycle.edges.is_empty())
  let mut sum = @bigint.BigInt::from_int(0)
  let seen : Map[Int, Unit] = Map([])
  for i, item in cycle.edges {
    assert_true(
      item.constraint_index >= 0 && item.constraint_index < constraints.length(),
    )
    assert_true(!seen.contains(item.constraint_index))
    seen[item.constraint_index] = ()
    assert_eq(item.constraint, constraints[item.constraint_index])
    let next = cycle.edges[(i + 1) % cycle.edges.length()]
    assert_eq(item.constraint.edge_to(), next.constraint.edge_from())
    sum = sum + @bigint.BigInt::from_int64(item.constraint.upper_bound_us())
  }
  assert_true(sum.compare_int(0) < 0)
  assert_eq(sum, @bigint.BigInt::from_int64(cycle.total_weight_us))
}

///|
fn check_component(
  analysis : @solver.ConstraintAnalysis,
  component : @solver.ComponentAnalysis,
) -> Unit raise {
  let constraints = component.constraint_indices
    .iter()
    .map(i => analysis.constraints[i])
    .collect()
  match component.outcome {
    @solver.ComponentFeasible(offsets~, intervals~) => {
      assert_eq(offsets.length(), component.clocks.length())
      assert_eq(intervals.length(), component.clocks.length())
      verify_assignment(constraints, offsets)
      for i, offset in offsets {
        assert_eq(offset.clock_id, component.clocks[i])
        assert_eq(intervals[i].clock_id, offset.clock_id)
        if offset.clock_id == component.reference_clock {
          assert_eq(offset.offset_us, 0L)
        }
        match intervals[i].lower {
          @solver.Finite(lower) => assert_true(offset.offset_us >= lower)
          @solver.Unbounded => ()
        }
        match intervals[i].upper {
          @solver.Finite(upper) => assert_true(offset.offset_us <= upper)
          @solver.Unbounded => ()
        }
      }
    }
    @solver.ComponentInfeasible(cycle~) => {
      verify_cycle(analysis.constraints, cycle)
      for item in cycle.edges {
        assert_true(
          component.constraint_indices.contains(item.constraint_index),
        )
      }
    }
    @solver.ComponentFailed(_) => fail("unexpected component error")
  }
}
