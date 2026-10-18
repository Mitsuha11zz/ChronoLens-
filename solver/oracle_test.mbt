///|
/// Independent dense Floyd-Warshall implementation for small bounded weights.
/// It shares no relaxation, graph-indexing, or cycle-extraction helper.
fn floyd(
  constraints : ArrayView[@model.DifferenceConstraint],
  clocks : ArrayView[String],
) -> Array[Array[Int64?]] {
  let indices : Map[String, Int] = Map([])
  let matrix : Array[Array[Int64?]] = []
  for i, clock in clocks {
    indices[clock] = i
    let row : Array[Int64?] = Array::make(clocks.length(), None)
    row[i] = Some(0L)
    matrix.push(row)
  }
  for constraint in constraints {
    let from = indices[constraint.edge_from()]
    let to = indices[constraint.edge_to()]
    let weight = constraint.upper_bound_us()
    match matrix[from][to] {
      None => matrix[from][to] = Some(weight)
      Some(previous) => if weight < previous { matrix[from][to] = Some(weight) }
    }
  }
  for k = 0; k < clocks.length(); k = k + 1 {
    for i = 0; i < clocks.length(); i = i + 1 {
      for j = 0; j < clocks.length(); j = j + 1 {
        match (matrix[i][k], matrix[k][j]) {
          (Some(a), Some(b)) => {
            let candidate = a + b
            match matrix[i][j] {
              None => matrix[i][j] = Some(candidate)
              Some(previous) =>
                if candidate < previous {
                  matrix[i][j] = Some(candidate)
                }
            }
          }
          _ => ()
        }
      }
    }
  }
  matrix
}

///|
fn compare_oracle(
  constraints : ArrayView[@model.DifferenceConstraint],
  clocks : ArrayView[String],
) -> Unit raise {
  let distances = floyd(constraints, clocks)
  let indices : Map[String, Int] = Map([])
  let weak : Array[Array[Bool]] = []
  let mut conflict = false
  for i, clock in clocks {
    indices[clock] = i
    if distances[i][i].unwrap() < 0L {
      conflict = true
    }
    let row = Array::make(clocks.length(), false)
    row[i] = true
    weak.push(row)
  }
  for constraint in constraints {
    let a = indices[constraint.edge_from()]
    let b = indices[constraint.edge_to()]
    weak[a][b] = true
    weak[b][a] = true
  }
  // Boolean transitive closure independently checks the weak partition.
  for k = 0; k < clocks.length(); k = k + 1 {
    for i = 0; i < clocks.length(); i = i + 1 {
      for j = 0; j < clocks.length(); j = j + 1 {
        weak[i][j] = weak[i][j] || (weak[i][k] && weak[k][j])
      }
    }
  }
  let solved = @solver.solve_constraints(constraints, clock_ids=clocks)
  match solved.outcome {
    @solver.Feasible(offsets~) => {
      assert_true(!conflict)
      verify_assignment(constraints, offsets)
    }
    @solver.Infeasible(cycle~) => {
      assert_true(conflict)
      verify_cycle(constraints, cycle)
    }
  }
  let analysis = @solver.analyze_constraints(constraints, clock_ids=clocks)
  let memberships : Map[String, Int] = Map([])
  let covered_edges : Map[Int, Unit] = Map([])
  for component in analysis.components {
    let mut component_conflict = false
    for clock in component.clocks {
      assert_true(!memberships.contains(clock))
      memberships[clock] = component.component_id
      let index = indices[clock]
      if distances[index][index].unwrap() < 0L {
        component_conflict = true
      }
    }
    for index in component.constraint_indices {
      assert_true(!covered_edges.contains(index))
      covered_edges[index] = ()
    }
    check_component(analysis, component)
    match component.outcome {
      @solver.ComponentInfeasible(_) => assert_true(component_conflict)
      @solver.ComponentFeasible(intervals~, ..) => {
        assert_true(!component_conflict)
        let reference = indices[component.reference_clock]
        for interval in intervals {
          let i = indices[interval.clock_id]
          let expected_upper = match distances[reference][i] {
            None => @solver.Unbounded
            Some(value) => @solver.Finite(value)
          }
          let expected_lower = match distances[i][reference] {
            None => @solver.Unbounded
            Some(value) => @solver.Finite(-value)
          }
          assert_eq(interval.upper, expected_upper)
          assert_eq(interval.lower, expected_lower)
        }
      }
      _ => fail("small graphs must not exhaust resources or overflow")
    }
  }
  assert_eq(memberships.length(), clocks.length())
  assert_eq(covered_edges.length(), constraints.length())
  for i, a in clocks {
    for j, b in clocks {
      assert_eq(memberships[a] == memberships[b], weak[i][j])
    }
  }
}

///|
test "all 256 two-clock graphs agree with independent Floyd-Warshall" {
  let clocks = ["A", "B"]
  for code = 0; code < 256; code = code + 1 {
    let constraints : Array[@model.DifferenceConstraint] = []
    let mut rest = code
    for i = 0; i < 2; i = i + 1 {
      for j = 0; j < 2; j = j + 1 {
        let digit = rest % 4
        rest = rest / 4
        if digit != 0 {
          constraints.push(edge(clocks[i], clocks[j], (digit - 2).to_int64()))
        }
      }
    }
    compare_oracle(constraints, clocks)
  }
}

///|
test "128 reproducible four-clock graphs agree on feasibility partitions and intervals" {
  let clocks = ["A", "B", "C", "D"]
  let latent = [-3L, 2L, -1L, 4L]
  for case_id = 0; case_id < 128; case_id = case_id + 1 {
    let constraints : Array[@model.DifferenceConstraint] = []
    let mut state = (case_id + 1) * 101
    for i = 0; i < 4; i = i + 1 {
      for j = 0; j < 4; j = j + 1 {
        state = (state * 25173 + 13849) % 65536
        if i != j && state % 4 != 0 {
          let weight = if case_id < 64 {
            (state / 4 % 9 - 4).to_int64()
          } else {
            latent[j] - latent[i] + (state / 4 % 5).to_int64()
          }
          constraints.push(edge(clocks[i], clocks[j], weight))
        }
      }
    }
    compare_oracle(constraints, clocks)
    if case_id >= 64 {
      match @solver.solve_constraints(constraints, clock_ids=clocks).outcome {
        @solver.Feasible(_) => ()
        _ => fail("generated graph contains a known feasible assignment")
      }
    }
  }
}
