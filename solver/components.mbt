///|
fn find_root(parents : Array[Int], node : Int) -> Int {
  let mut root = node
  while parents[root] != root {
    root = parents[root]
  }
  root
}

///|
/// Group weakly connected vertices, retaining global constraint indices.
fn partition_graph(
  graph : Graph,
  budget : Budget,
) -> Array[Graph] raise SolveError {
  let parents = Array::make(graph.clocks.length(), 0)
  let sizes = Array::make(graph.clocks.length(), 1)
  for i = 0; i < parents.length(); i = i + 1 {
    parents[i] = i
  }
  for edge in graph.edges {
    budget.visit()
    let a = find_root(parents, edge.from)
    let b = find_root(parents, edge.to)
    if a != b {
      if sizes[a] >= sizes[b] {
        parents[b] = a
        sizes[a] += sizes[b]
      } else {
        parents[a] = b
        sizes[b] += sizes[a]
      }
    }
  }
  let root_groups : Map[Int, Int] = Map([])
  let components : Array[Graph] = []
  let group_ids = Array::make(graph.clocks.length(), -1)
  let local_ids = Array::make(graph.clocks.length(), -1)
  for i, clock in graph.clocks {
    let root = find_root(parents, i)
    let group = match root_groups.get(root) {
      Some(group) => group
      None => {
        let group = components.length()
        root_groups[root] = group
        components.push({
          clocks: [],
          constraints: graph.constraints,
          edges: [],
        })
        group
      }
    }
    group_ids[i] = group
    local_ids[i] = components[group].clocks.length()
    components[group].clocks.push(clock)
  }
  for edge in graph.edges {
    budget.visit()
    components[group_ids[edge.from]].edges.push({
      from: local_ids[edge.from],
      to: local_ids[edge.to],
      index: edge.index,
      weight: edge.weight,
    })
  }
  components
}
