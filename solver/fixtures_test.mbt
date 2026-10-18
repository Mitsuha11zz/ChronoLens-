///|
/// Embedded from the current fixtures input for cross-backend execution.
fn fixture_four() -> String {
  let text =
    #|{"event_id":"a1","clock_id":"A","trace_id":"t1","message_id":"request-1","attempt":0,"kind":"send","ts_us":"1000000"}
    #|{"event_id":"b1","clock_id":"B","trace_id":"t1","message_id":"request-1","attempt":0,"kind":"receive","ts_us":"900000"}
    #|{"event_id":"b2","clock_id":"B","trace_id":"t1","message_id":"response-1","attempt":0,"kind":"send","ts_us":"940000"}
    #|{"event_id":"a2","clock_id":"A","trace_id":"t1","message_id":"response-1","attempt":0,"kind":"receive","ts_us":"1100000"}
  text
}

///|
/// Embedded from the current fixtures input for cross-backend execution.
fn fixture_negative() -> String {
  let text =
    #|{"event_id":"ab-send","clock_id":"A","trace_id":"cycle","message_id":"ab","attempt":0,"kind":"send","ts_us":"100"}
    #|{"event_id":"ab-receive","clock_id":"B","trace_id":"cycle","message_id":"ab","attempt":0,"kind":"receive","ts_us":"90"}
    #|{"event_id":"bc-send","clock_id":"B","trace_id":"cycle","message_id":"bc","attempt":0,"kind":"send","ts_us":"100"}
    #|{"event_id":"bc-receive","clock_id":"C","trace_id":"cycle","message_id":"bc","attempt":0,"kind":"receive","ts_us":"90"}
    #|{"event_id":"ca-send","clock_id":"C","trace_id":"cycle","message_id":"ca","attempt":0,"kind":"send","ts_us":"100"}
    #|{"event_id":"ca-receive","clock_id":"A","trace_id":"cycle","message_id":"ca","attempt":0,"kind":"receive","ts_us":"90"}
  text
}

///|
/// Embedded from the current fixtures input for cross-backend execution.
fn fixture_components() -> String {
  let text =
    #|{"event_id":"a-send","clock_id":"A","trace_id":"bounded","message_id":"request","attempt":0,"kind":"send","ts_us":"1000000"}
    #|{"event_id":"b-receive","clock_id":"B","trace_id":"bounded","message_id":"request","attempt":0,"kind":"receive","ts_us":"900000"}
    #|{"event_id":"b-send","clock_id":"B","trace_id":"bounded","message_id":"response","attempt":0,"kind":"send","ts_us":"940000"}
    #|{"event_id":"a-receive","clock_id":"A","trace_id":"bounded","message_id":"response","attempt":0,"kind":"receive","ts_us":"1100000"}
    #|{"event_id":"c-send","clock_id":"C","trace_id":"one-way","message_id":"cd","attempt":0,"kind":"send","ts_us":"100"}
    #|{"event_id":"d-receive","clock_id":"D","trace_id":"one-way","message_id":"cd","attempt":0,"kind":"receive","ts_us":"150"}
    #|{"event_id":"e-send","clock_id":"E","trace_id":"isolated","message_id":"missing","attempt":0,"kind":"send","ts_us":"100"}
    #|{"event_id":"f-send","clock_id":"F","trace_id":"conflict","message_id":"self","attempt":0,"kind":"send","ts_us":"100"}
    #|{"event_id":"f-receive","clock_id":"F","trace_id":"conflict","message_id":"self","attempt":0,"kind":"receive","ts_us":"90"}
  text
}

///|
fn build_fixture(
  text : String,
  path : String,
) -> @constraints.ConstraintSet raise {
  let input = @input.parse_jsonl(text, source_path=path)
  assert_true(input.is_valid())
  @constraints.build(@correlate.correlate_input(input))
}

///|
test "four-event pipeline returns the exact 100 to 160 millisecond interval" {
  let built = build_fixture(fixture_four(), "four-events.jsonl")
  let report = @solver.analyze(built, reference_clock="A")
  assert_eq(report.input, built)
  assert_eq(report.analysis.components.length(), 1)
  let component = report.analysis.components[0]
  check_component(report.analysis, component)
  assert_eq(component.reference_clock, "A")
  match component.outcome {
    @solver.ComponentFeasible(offsets~, intervals~) => {
      assert_eq(offsets[0].offset_us, 0L)
      assert_eq(offsets[1].offset_us, 100000L)
      assert_eq(intervals[0].lower, @solver.Finite(0L))
      assert_eq(intervals[0].upper, @solver.Finite(0L))
      assert_eq(intervals[1].lower, @solver.Finite(100000L))
      assert_eq(intervals[1].upper, @solver.Finite(160000L))
    }
    _ => fail("expected finite interval")
  }
  assert_eq(built.constraints[0].constraint.upper_bound_us(), -100000L)
  assert_eq(built.constraints[1].constraint.upper_bound_us(), 160000L)
}

///|
test "switching reference changes coordinates and interval signs" {
  let report = @solver.analyze(
    build_fixture(fixture_four(), "four-events.jsonl"),
    reference_clock="B",
  )
  let component = report.analysis.components[0]
  check_component(report.analysis, component)
  assert_eq(component.reference_clock, "B")
  match component.outcome {
    @solver.ComponentFeasible(offsets~, intervals~) => {
      assert_eq(offsets[1].offset_us, 0L)
      assert_eq(intervals[0].lower, @solver.Finite(-160000L))
      assert_eq(intervals[0].upper, @solver.Finite(-100000L))
      assert_eq(intervals[1].lower, @solver.Finite(0L))
      assert_eq(intervals[1].upper, @solver.Finite(0L))
    }
    _ => fail("expected feasible component")
  }
}

///|
test "negative-cycle fixture has a closed negative 30 microsecond witness" {
  let built = build_fixture(fixture_negative(), "negative-cycle.jsonl")
  let solved = @solver.solve(built)
  assert_eq(solved.input, built)
  match solved.solution.outcome {
    @solver.Infeasible(cycle~) => {
      verify_cycle(solved.solution.constraints, cycle)
      assert_eq(cycle.total_weight_us, -30L)
      assert_eq(cycle.edges.length(), 3)
      for item in cycle.edges {
        match built.constraints[item.constraint_index].evidence {
          @constraints.Message(pair~, tolerance_us~) => {
            assert_eq(tolerance_us, 0L)
            assert_eq(
              pair.send_event.source().unwrap().path(),
              "negative-cycle.jsonl",
            )
          }
          _ => fail("expected source messages")
        }
      }
    }
    _ => fail("expected fixture conflict")
  }
}

///|
test "mixed components keep finite unbounded isolated and conflicting results independent" {
  let built = build_fixture(fixture_components(), "component-analysis.jsonl")
  let report = @solver.analyze(built, reference_clock="A")
  let analysis = report.analysis
  assert_eq(analysis.components.length(), 4)
  assert_eq(analysis.clocks.length(), 6)
  assert_eq(analysis.constraints.length(), 4)
  assert_eq(report.input.correlation.unresolved.length(), 1)
  let mut component_visits = 0L
  for i, component in analysis.components {
    assert_eq(component.component_id, i)
    check_component(analysis, component)
    component_visits += component.stats.edge_visits
  }
  assert_eq(analysis.stats.edge_visits, component_visits + 8L)
  assert_eq(analysis.components[0].reference_clock, "A")
  assert_eq(analysis.components[1].reference_clock, "C")
  assert_eq(analysis.components[2].reference_clock, "E")
  assert_eq(analysis.components[3].reference_clock, "F")
  match analysis.components[1].outcome {
    @solver.ComponentFeasible(intervals~, ..) => {
      assert_eq(intervals[1].lower, @solver.Finite(-50L))
      assert_eq(intervals[1].upper, @solver.Unbounded)
    }
    _ => fail("expected one-sided interval")
  }
  match analysis.components[2].outcome {
    @solver.ComponentFeasible(intervals~, ..) => {
      assert_eq(intervals[0].lower, @solver.Finite(0L))
      assert_eq(intervals[0].upper, @solver.Finite(0L))
      assert_eq(analysis.components[2].constraint_indices.length(), 0)
    }
    _ => fail("expected isolated clock")
  }
  match analysis.components[3].outcome {
    @solver.ComponentInfeasible(cycle~) => {
      // Correlation explicitly uses MoonBit shortlex comparison, so this
      // is the fourth original edge, not the component-local edge zero.
      assert_eq(cycle.edges[0].constraint_index, 3)
      let item = built.constraints[cycle.edges[0].constraint_index]
      match item.evidence {
        @constraints.Message(pair~, ..) =>
          assert_eq(pair.send_event.event_id(), "f-send")
        _ => fail("expected f message evidence")
      }
    }
    _ => fail("expected self-loop conflict")
  }
}

///|
test "message and prior conflicts retain both kinds of evidence" {
  let paired = @correlate.correlate_input(@input.parse_jsonl(fixture_four()))
  let prior = @constraints.OffsetPrior::new(
    clock_id="B",
    reference_clock="A",
    label="operator",
    upper_us=50000L,
  )
  let built = @constraints.build(paired, priors=[prior])
  let report = @solver.analyze(built)
  match report.analysis.components[0].outcome {
    @solver.ComponentInfeasible(cycle~) => {
      verify_cycle(report.analysis.constraints, cycle)
      let mut message_seen = false
      let mut prior_seen = false
      for item in cycle.edges {
        match built.constraints[item.constraint_index].evidence {
          @constraints.Message(..) => message_seen = true
          @constraints.Prior(prior~, ..) => {
            prior_seen = true
            assert_eq(prior.label, "operator")
          }
        }
      }
      assert_true(message_seen && prior_seen)
    }
    _ => fail("expected inconsistent prior")
  }
}

///|
test "shuffled typed events yield the same canonical built analysis" {
  let input = @input.parse_jsonl(fixture_components())
  let events = Array::from_iter(input.accepted_events.iter())
  let reversed : Array[@model.Event] = []
  for i = events.length() - 1; i >= 0; i = i - 1 {
    reversed.push(events[i])
  }
  let one = @constraints.build(@correlate.correlate(events))
  let two = @constraints.build(@correlate.correlate(reversed))
  assert_eq(@solver.analyze(one), @solver.analyze(two))
}
