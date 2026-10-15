///|
fn predecessor_edge(
  node : Int,
  predecessors : Array[Int],
  graph : Graph,
  budget : Budget,
) -> IndexedEdge raise SolveError {
  budget.visit()
  let index = predecessors[node]
  if index < 0 || index >= graph.edges.length() {
    raise InvalidWitness
  }
  let edge = graph.edges[index]
  if edge.to != node {
    raise InvalidWitness
  }
  edge
}

///|
fn extract_cycle(
  updated_node : Int,
  predecessors : Array[Int],
  graph : Graph,
  budget : Budget,
) -> NegativeCycle raise SolveError {
  // V predecessor steps move from a relaxed vertex into a cycle.
  let mut node = updated_node
  for _i = 0; _i < graph.clocks.length(); _i = _i + 1 {
    node = predecessor_edge(node, predecessors, graph, budget).from
  }
  let start = node
  let backward : Array[IndexedEdge] = []
  for _i = 0; _i < graph.clocks.length(); _i = _i + 1 {
    let edge = predecessor_edge(node, predecessors, graph, budget)
    backward.push(edge)
    node = edge.from
    if node == start {
      break
    }
  }
  if backward.is_empty() || node != start {
    raise InvalidWitness
  }
  // Reverse the predecessor walk to obtain forward-oriented evidence.
  let ordered : Array[IndexedEdge] = []
  for i = backward.length() - 1; i >= 0; i = i - 1 {
    ordered.push(backward[i])
  }
  // Canonical rotation picks the earliest original edge, without reordering it.
  let mut first = 0
  for i = 1; i < ordered.length(); i = i + 1 {
    if ordered[i].index < ordered[first].index {
      first = i
    }
  }
  let evidence : Array[CycleEdge] = []
  for i = 0; i < ordered.length(); i = i + 1 {
    budget.visit()
    let edge = ordered[(first + i) % ordered.length()]
    let next = ordered[(first + i + 1) % ordered.length()]
    if edge.to != next.from {
      raise InvalidWitness
    }
    evidence.push({
      constraint_index: edge.index,
      constraint: graph.constraints[edge.index],
    })
  }
  let total = sum_cycle_weights(ordered, budget)
  if total >= 0L {
    raise InvalidWitness
  }
  { edges: ReadOnlyArray::from_array(evidence), total_weight_us: total, }
}

///|
/// Add opposite signs when possible, so an intermediate sum cannot overflow
/// if the exact final total fits Int64. Edge evidence keeps traversal order.
fn sum_cycle_weights(
  edges : Array[IndexedEdge],
  budget : Budget,
) -> Int64 raise SolveError {
  let positive : Array[IndexedEdge] = []
  let negative : Array[IndexedEdge] = []
  for edge in edges {
    budget.visit()
    if edge.weight >= 0L {
      positive.push(edge)
    } else {
      negative.push(edge)
    }
  }
  let mut p = 0
  let mut n = 0
  let mut total = 0L
  while p < positive.length() || n < negative.length() {
    budget.visit()
    let edge = if n < negative.length() &&
      (total >= 0L || p >= positive.length()) {
      let edge = negative[n]
      n += 1
      edge
    } else {
      let edge = positive[p]
      p += 1
      edge
    }
    total = checked_add(total, edge.weight, CycleWeightSum, edge.index)
  }
  total
}

///|
fn verify_offsets(
  distances : Array[Int64],
  graph : Graph,
  budget : Budget,
) -> Unit raise SolveError {
  for edge in graph.edges {
    budget.visit()
    // Compare to a checked sum instead of subtracting two offsets.
    let upper = checked_add(
      distances[edge.from],
      edge.weight,
      FeasibleVerification,
      edge.index,
    )
    if distances[edge.to] > upper {
      raise InvalidWitness
    }
  }
}
