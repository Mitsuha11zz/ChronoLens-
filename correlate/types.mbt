///|
#derive(Debug, Eq)
pub(all) enum CorrelationIssueKind {
  MissingSend
  MissingReceive
  Ambiguous
}

///|
/// Exactly one send and one receive sharing a complete message key.
#derive(Debug, Eq)
pub struct MessagePair {
  key : @model.MessageKey
  send_event : @model.Event
  receive_event : @model.Event
}

///|
/// All evidence remains available when a group cannot be uniquely paired.
/// Missing-side and ambiguity diagnostics can coexist.
#derive(Debug, Eq)
pub struct UnresolvedGroup {
  key : @model.MessageKey
  send_events : ReadOnlyArray[@model.Event]
  receive_events : ReadOnlyArray[@model.Event]
  issues : ReadOnlyArray[CorrelationIssueKind]
}

///|
/// Missing and ambiguous group counts can overlap.
#derive(Debug, Eq)
pub struct CorrelationStats {
  total_events : Int
  group_count : Int
  paired_groups : Int
  unresolved_groups : Int
  missing_groups : Int
  ambiguous_groups : Int
}

///|
#derive(Debug, Eq)
pub struct CorrelationReport {
  pairs : ReadOnlyArray[MessagePair]
  unresolved : ReadOnlyArray[UnresolvedGroup]
  stats : CorrelationStats
}

///|
/// Empty event collections are vacuously paired; inspect total_events for coverage.
pub fn CorrelationReport::fully_paired(self : CorrelationReport) -> Bool {
  self.unresolved.is_empty()
}

///|
#deprecated
pub extend CorrelationIssueKind with @debug.Debug::{to_repr}

///|
#deprecated
pub extend CorrelationIssueKind with Eq::{equal, not_equal}

///|
#deprecated
pub extend MessagePair with @debug.Debug::{to_repr}

///|
#deprecated
pub extend MessagePair with Eq::{equal, not_equal}

///|
#deprecated
pub extend UnresolvedGroup with @debug.Debug::{to_repr}

///|
#deprecated
pub extend UnresolvedGroup with Eq::{equal, not_equal}

///|
#deprecated
pub extend CorrelationStats with @debug.Debug::{to_repr}

///|
#deprecated
pub extend CorrelationStats with Eq::{equal, not_equal}

///|
#deprecated
pub extend CorrelationReport with @debug.Debug::{to_repr}

///|
#deprecated
pub extend CorrelationReport with Eq::{equal, not_equal}
