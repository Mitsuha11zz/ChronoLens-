///|
/// Caps apply before returning any verdict. Edge visits include relaxation,
/// predecessor traversal, and result verification, but not graph indexing.
pub struct SolveLimits {
  max_clocks : Int
  max_constraints : Int
  max_edge_visits : Int64
}

///|
pub fn SolveLimits::new(
  max_clocks? : Int = 256,
  max_constraints? : Int = 20000,
  max_edge_visits? : Int64 = 5000000L,
) -> SolveLimits raise SolveError {
  if max_clocks <= 0 || max_clocks > 4096 {
    raise InvalidLimit("max_clocks")
  }
  if max_constraints <= 0 || max_constraints > 2000000 {
    raise InvalidLimit("max_constraints")
  }
  if max_edge_visits <= 0L || max_edge_visits > 1000000000L {
    raise InvalidLimit("max_edge_visits")
  }
  { max_clocks, max_constraints, max_edge_visits, }
}

///|
pub impl Default for SolveLimits with fn default() {
  { max_clocks: 256, max_constraints: 20000, max_edge_visits: 5000000L, }
}

///|
pub extend SolveLimits with Default::{default}

///|
priv struct Budget {
  limit : Int64
  mut used : Int64
}

///|
fn Budget::visit(self : Budget) -> Unit raise SolveError {
  if self.used >= self.limit {
    raise EdgeVisitLimitExceeded(self.limit)
  }
  self.used += 1L
}
