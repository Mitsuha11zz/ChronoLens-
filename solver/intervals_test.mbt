///|
test "single forward edge leaves the lower bound unbounded" {
  let result = @solver.analyze_constraints(
    [edge("A", "B", 50L)],
    reference_clock="A",
  )
  let component = result.components[0]
  check_component(result, component)
  match component.outcome {
    @solver.ComponentFeasible(intervals~, ..) => {
      assert_eq(intervals[1].lower, @solver.Unbounded)
      assert_eq(intervals[1].upper, @solver.Finite(50L))
    }
    _ => fail("expected feasible interval")
  }
}

///|
test "single reverse edge leaves the upper bound unbounded" {
  let result = @solver.analyze_constraints(
    [edge("B", "A", -100L)],
    reference_clock="A",
  )
  check_component(result, result.components[0])
  match result.components[0].outcome {
    @solver.ComponentFeasible(intervals~, ..) => {
      assert_eq(intervals[1].lower, @solver.Finite(100L))
      assert_eq(intervals[1].upper, @solver.Unbounded)
    }
    _ => fail("expected feasible interval")
  }
}

///|
test "a weakly connected clock can be unbounded on both sides" {
  let result = @solver.analyze_constraints(
    [edge("A", "C", 10L), edge("B", "C", 20L)],
    reference_clock="A",
  )
  assert_eq(result.components.length(), 1)
  check_component(result, result.components[0])
  match result.components[0].outcome {
    @solver.ComponentFeasible(intervals~, ..) => {
      assert_eq(intervals[1].clock_id, "B")
      assert_eq(intervals[1].lower, @solver.Unbounded)
      assert_eq(intervals[1].upper, @solver.Unbounded)
    }
    _ => fail("expected feasible interval")
  }
}

///|
test "references are component-local and unknown clocks are rejected" {
  let constraints = [edge("A", "B", 1L), edge("C", "D", 1L)]
  let result = @solver.analyze_constraints(constraints, reference_clock="D")
  assert_eq(result.components[0].reference_clock, "A")
  assert_eq(result.components[1].reference_clock, "D")
  for component in result.components {
    check_component(result, component)
  }
  assert_eq(
    analysis_error(() => {
      @solver.analyze_constraints(constraints, reference_clock="Z")
    }),
    @solver.UnknownReferenceClock("Z"),
  )
}

///|
test "default reference and component ordering use lexical rather than length order" {
  let result = @solver.analyze_constraints([edge("Z", "AA", 1L)], clock_ids=[
    "B",
  ])
  assert_eq(Array::from_iter(result.clocks.iter()), ["AA", "B", "Z"])
  assert_eq(result.components[0].reference_clock, "AA")
  assert_eq(result.components[1].reference_clock, "B")
  for component in result.components {
    check_component(result, component)
  }
}

///|
test "empty and isolated analysis explicitly has no cross-component baseline" {
  assert_eq(@solver.analyze_constraints([]).components.length(), 0)
  let result = @solver.analyze_constraints([], clock_ids=["Z", "A"])
  assert_eq(result.components.length(), 2)
  for component in result.components {
    check_component(result, component)
  }
  assert_eq(result.components[0].reference_clock, "A")
  assert_eq(result.components[1].reference_clock, "Z")
  assert_eq(
    analysis_error(() => @solver.analyze_constraints([], reference_clock="A")),
    @solver.UnknownReferenceClock("A"),
  )
}

///|
test "overflow in one component does not block a separate feasible component" {
  let constraints = [
    edge("A", "B", @int64.MIN_VALUE),
    edge("B", "C", -1L),
    edge("D", "E", 5L),
  ]
  let result = @solver.analyze_constraints(constraints)
  assert_eq(result.components.length(), 2)
  match result.components[0].outcome {
    @solver.ComponentFailed(error~) =>
      assert_eq(
        error,
        @solver.ArithmeticOverflow(phase=@solver.Relaxation, constraint_index=1),
      )
    _ => fail("expected arithmetic failure")
  }
  check_component(result, result.components[1])
}

///|
test "coordinate overflow does not masquerade as unboundedness" {
  let result = @solver.analyze_constraints(
    [edge("A", "B", @int64.MIN_VALUE)],
    reference_clock="B",
  )
  match result.components[0].outcome {
    @solver.ComponentFailed(error~) =>
      assert_eq(
        error,
        @solver.OffsetOverflow(clock_id="A", reference_clock="B"),
      )
    _ => fail("expected unrepresentable coordinate")
  }
}

///|
test "upper and reverse path overflow remain explicit failures" {
  let forward = @solver.analyze_constraints([
    edge("A", "B", @int64.MAX_VALUE),
    edge("B", "C", 1L),
  ])
  match forward.components[0].outcome {
    @solver.ComponentFailed(error~) =>
      assert_eq(
        error,
        @solver.ArithmeticOverflow(
          phase=@solver.UpperBoundPaths,
          constraint_index=1,
        ),
      )
    _ => fail("expected upper-path overflow")
  }
  let reverse = @solver.analyze_constraints([
    edge("B", "A", @int64.MAX_VALUE),
    edge("C", "B", 1L),
  ])
  match reverse.components[0].outcome {
    @solver.ComponentFailed(error~) =>
      assert_eq(
        error,
        @solver.ArithmeticOverflow(
          phase=@solver.LowerBoundPaths,
          constraint_index=1,
        ),
      )
    _ => fail("expected reverse-path overflow")
  }
}

///|
test "minimum finite upper bound stays finite" {
  let result = @solver.analyze_constraints(
    [edge("A", "B", @int64.MIN_VALUE)],
    reference_clock="A",
  )
  check_component(result, result.components[0])
  match result.components[0].outcome {
    @solver.ComponentFeasible(intervals~, ..) => {
      assert_eq(intervals[1].upper, @solver.Finite(@int64.MIN_VALUE))
      assert_eq(intervals[1].lower, @solver.Unbounded)
    }
    _ => fail("expected minimum finite bound")
  }
}

///|
test "normalized verification handles mathematically overflowing RHS" {
  let result = @solver.analyze_constraints(
    [edge("A", "B", -10L), edge("A", "C", @int64.MAX_VALUE)],
    reference_clock="B",
  )
  check_component(result, result.components[0])
  match result.components[0].outcome {
    @solver.ComponentFeasible(offsets~, ..) => {
      assert_eq(offsets[0].offset_us, 10L)
      assert_eq(offsets[1].offset_us, 0L)
      assert_eq(offsets[2].offset_us, 10L)
    }
    _ => fail("expected representable valid assignment")
  }
}

///|
test "partition budget failures reject the whole call" {
  let constraints = [edge("A", "B", 1L)]
  let limits = @solver.SolveLimits::new(max_edge_visits=1L)
  assert_eq(
    analysis_error(() => @solver.analyze_constraints(constraints, limits~)),
    @solver.EdgeVisitLimitExceeded(1L),
  )
}

///|
test "shared budget exhaustion keeps later components explicitly failed" {
  let constraints = [edge("A", "B", 1L), edge("C", "D", 1L)]
  let limits = @solver.SolveLimits::new(max_edge_visits=5L)
  let result = @solver.analyze_constraints(constraints, limits~)
  assert_eq(result.stats.edge_visits, 5L)
  for component in result.components {
    match component.outcome {
      @solver.ComponentFailed(error~) =>
        assert_eq(error, @solver.EdgeVisitLimitExceeded(5L))
      _ => fail("expected failed components")
    }
  }
}
