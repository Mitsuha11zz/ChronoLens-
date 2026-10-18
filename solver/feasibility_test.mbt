///|
test "empty graph and isolated clocks have zero evidence" {
  let empty = @solver.solve_constraints([])
  assert_eq(empty.clocks.length(), 0)
  assert_eq(empty.stats.edge_visits, 0L)
  match empty.outcome {
    @solver.Feasible(offsets~) => assert_eq(offsets.length(), 0)
    _ => fail("empty graph must be feasible")
  }
  let isolated = @solver.solve_constraints([], clock_ids=["Z", "A"])
  assert_eq(Array::from_iter(isolated.clocks.iter()), ["A", "Z"])
  match isolated.outcome {
    @solver.Feasible(offsets~) => {
      assert_eq(offsets.length(), 2)
      for offset in offsets {
        assert_eq(offset.offset_us, 0L)
      }
    }
    _ => fail("isolated clocks must be feasible")
  }
}

///|
test "feasible paths and zero cycles satisfy every original edge" {
  let constraints = [
    edge("A", "B", -10L),
    edge("B", "C", -20L),
    edge("C", "A", 30L),
    edge("A", "B", 100L),
  ]
  let result = @solver.solve_constraints(constraints)
  assert_eq(result.constraints.length(), constraints.length())
  match result.outcome {
    @solver.Feasible(offsets~) => verify_assignment(constraints, offsets)
    _ => fail("expected feasible zero cycle")
  }
}

///|
test "negative cycle retains provenance and exact negative sum" {
  let constraints = [
    edge("A", "B", -10L, label="ab"),
    edge("B", "C", -10L, label="bc"),
    edge("C", "A", -10L, label="ca"),
  ]
  let result = @solver.solve_constraints(constraints)
  match result.outcome {
    @solver.Infeasible(cycle~) => {
      verify_cycle(constraints, cycle)
      assert_eq(cycle.edges.length(), 3)
      assert_eq(cycle.edges[0].constraint_index, 0)
      assert_eq(cycle.total_weight_us, -30L)
    }
    _ => fail("expected negative cycle")
  }
}

///|
test "predecessor traversal removes downstream tails" {
  let constraints = [
    edge("A", "B", -1L),
    edge("B", "A", 0L),
    edge("B", "C", 0L),
    edge("C", "D", 0L),
  ]
  match @solver.solve_constraints(constraints).outcome {
    @solver.Infeasible(cycle~) => {
      verify_cycle(constraints, cycle)
      assert_eq(cycle.edges.length(), 2)
      for item in cycle.edges {
        assert_true(item.constraint_index < 2)
      }
    }
    _ => fail("expected two-edge cycle")
  }
}

///|
test "minimum negative self-loop is detected without repeated underflow" {
  let constraints = [edge("B", "B", @int64.MIN_VALUE)]
  match
    @solver.solve_constraints(constraints, clock_ids=["A", "B", "C"]).outcome {
    @solver.Infeasible(cycle~) => {
      verify_cycle(constraints, cycle)
      assert_eq(cycle.total_weight_us, @int64.MIN_VALUE)
      assert_eq(cycle.edges.length(), 1)
    }
    _ => fail("expected self-loop witness")
  }
}

///|
test "nonnegative self-loops are feasible" {
  let constraints = [edge("A", "A", 0L), edge("A", "A", @int64.MAX_VALUE)]
  match @solver.solve_constraints(constraints).outcome {
    @solver.Feasible(offsets~) => verify_assignment(constraints, offsets)
    _ => fail("nonnegative self-loop must be feasible")
  }
}

///|
test "path overflow is an error rather than an infeasibility verdict" {
  let constraints = [edge("A", "B", @int64.MIN_VALUE), edge("B", "C", -1L)]
  let error = solution_error(() => @solver.solve_constraints(constraints))
  assert_eq(
    error,
    @solver.ArithmeticOverflow(phase=@solver.Relaxation, constraint_index=1),
  )
}

///|
test "solver exact visit budget includes final assignment verification" {
  let constraints = [edge("A", "B", 1L)]
  let limits = @solver.SolveLimits::new(max_edge_visits=2L)
  let result = @solver.solve_constraints(constraints, limits~)
  assert_eq(result.stats.edge_visits, 2L)
  let tight = @solver.SolveLimits::new(max_edge_visits=1L)
  assert_eq(
    solution_error(() => @solver.solve_constraints(constraints, limits=tight)),
    @solver.EdgeVisitLimitExceeded(1L),
  )
}

///|
test "limits reject invalid settings before any analysis" {
  for value in [0, -1, 4097] {
    try @solver.SolveLimits::new(max_clocks=value) catch {
      error => assert_eq(error, @solver.InvalidLimit("max_clocks"))
    } noraise {
      _ => fail("expected invalid clock cap")
    }
  }
  for value in [0, -1, 2000001] {
    try @solver.SolveLimits::new(max_constraints=value) catch {
      error => assert_eq(error, @solver.InvalidLimit("max_constraints"))
    } noraise {
      _ => fail("expected invalid edge cap")
    }
  }
  for value in [0L, -1L, 1000000001L] {
    try @solver.SolveLimits::new(max_edge_visits=value) catch {
      error => assert_eq(error, @solver.InvalidLimit("max_edge_visits"))
    } noraise {
      _ => fail("expected invalid visit cap")
    }
  }
}

///|
test "clock and constraint caps reject oversized inputs" {
  let constraints = [edge("A", "B", 0L), edge("B", "C", 0L)]
  let clock_cap = @solver.SolveLimits::new(max_clocks=2)
  assert_eq(
    solution_error(() => {
      @solver.solve_constraints(constraints, limits=clock_cap)
    }),
    @solver.ClockLimitExceeded(2),
  )
  let edge_cap = @solver.SolveLimits::new(max_constraints=1)
  assert_eq(
    solution_error(() => @solver.solve_constraints(constraints, limits=edge_cap)),
    @solver.ConstraintLimitExceeded(1),
  )
  assert_eq(
    solution_error(() => {
      @solver.solve_constraints([], clock_ids=["A", "B", "C"], limits=clock_cap)
    }),
    @solver.ClockLimitExceeded(2),
  )
}

///|
test "blank isolated clock IDs are rejected while duplicate names collapse" {
  assert_eq(
    solution_error(() => @solver.solve_constraints([], clock_ids=[" "])),
    @solver.EmptyClockId,
  )
  let result = @solver.solve_constraints([], clock_ids=["A", "A"])
  assert_eq(result.clocks.length(), 1)
}

///|
test "solver results own a snapshot of caller constraint arrays" {
  let original = edge("A", "B", 1L)
  let constraints = [original]
  let result = @solver.solve_constraints(constraints)
  constraints.clear()
  assert_eq(result.constraints.length(), 1)
  assert_eq(result.constraints[0], original)
}

///|
test "repeated calls produce the same witness and stats" {
  let constraints = [edge("A", "B", -1L), edge("B", "A", 0L)]
  assert_eq(
    @solver.solve_constraints(constraints),
    @solver.solve_constraints(constraints),
  )
}
