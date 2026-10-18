///|
/// On a known-feasible graph, original distances give upper bounds, while
/// reversed distances give negated lower bounds. No path means unbounded.
fn reference_distances(
  graph : Graph,
  reference : Int,
  reverse : Bool,
  budget : Budget,
) -> Array[Int64?] raise SolveError {
  let distances : Array[Int64?] = Array::make(graph.clocks.length(), None)
  distances[reference] = Some(0L)
  let phase = if reverse { LowerBoundPaths } else { UpperBoundPaths }
  for pass = 0; pass < graph.clocks.length() - 1; pass = pass + 1 {
    if graph.edges.is_empty() {
      break
    }
    let mut changed = false
    for edge in graph.edges {
      budget.visit()
      let from = if reverse { edge.to } else { edge.from }
      let to = if reverse { edge.from } else { edge.to }
      if distances[from] is Some(distance) {
        let candidate = checked_add(distance, edge.weight, phase, edge.index)
        let improves = match distances[to] {
          None => true
          Some(previous) => candidate < previous
        }
        if improves {
          distances[to] = Some(candidate)
          changed = true
        }
      }
    }
    budget.passes += 1
    if !changed {
      break
    }
  }
  distances
}

///|
fn relative_offset(
  value : Int64,
  reference : Int64,
  clock_id : String,
  reference_clock : String,
) -> Int64 raise SolveError {
  if (reference > 0L && value < @int64.MIN_VALUE + reference) ||
    (reference < 0L && value > @int64.MAX_VALUE + reference) {
    raise OffsetOverflow(clock_id~, reference_clock~)
  }
  value - reference
}

///|
fn analyze_feasible(
  graph : Graph,
  offsets : ReadOnlyArray[ClockOffset],
  reference : Int,
  budget : Budget,
) -> ComponentOutcome raise SolveError {
  let reference_clock = graph.clocks[reference]
  let reference_value = offsets[reference].offset_us
  let normalized : Array[ClockOffset] = []
  let values : Array[Int64] = []
  for offset in offsets {
    let value = relative_offset(
      offset.offset_us,
      reference_value,
      offset.clock_id,
      reference_clock,
    )
    values.push(value)
    normalized.push({ clock_id: offset.clock_id, offset_us: value, })
  }
  // Verify the whole shared assignment after translation, never assemble
  // independent interval endpoints into a representative solution.
  verify_offsets(values, graph, budget)
  let upper = reference_distances(graph, reference, false, budget)
  let reversed = reference_distances(graph, reference, true, budget)
  let intervals : Array[OffsetInterval] = []
  for i, clock_id in graph.clocks {
    let lower_bound = match reversed[i] {
      None => Unbounded
      Some(distance) => {
        if distance == @int64.MIN_VALUE {
          raise BoundOverflow(clock_id~, lower_bound=true)
        }
        Finite(-distance)
      }
    }
    let upper_bound = match upper[i] {
      None => Unbounded
      Some(distance) => Finite(distance)
    }
    match lower_bound {
      Finite(lower) => if values[i] < lower { raise InvalidWitness }
      Unbounded => ()
    }
    match upper_bound {
      Finite(upper) => if values[i] > upper { raise InvalidWitness }
      Unbounded => ()
    }
    intervals.push({ clock_id, lower: lower_bound, upper: upper_bound, })
  }
  ComponentFeasible(
    offsets=ReadOnlyArray::from_array(normalized),
    intervals=ReadOnlyArray::from_array(intervals),
  )
}
