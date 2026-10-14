///|
pub(all) enum IssueKind {
  InvalidJson
  ExpectedObject
  EmptyInput
  MissingField(String)
  WrongType(String)
  UnknownField(String)
  DuplicateField(String)
  InvalidValue(String)
  DuplicateEventId(first_line~ : Int)
  LimitExceeded(String)
} derive(Debug, Eq)

///|
/// Physical input location, independent of any declared event source.
pub struct InputIssue {
  line : Int?
  kind : IssueKind
} derive(Debug, Eq)

///|
pub(all) enum InputStatus {
  Complete
  Limited(String)
} derive(Debug, Eq)

///|
/// Accepted events are previews until is_valid() is true.
pub struct InputReport {
  accepted_events : ReadOnlyArray[@model.Event]
  issues : ReadOnlyArray[InputIssue]
  status : InputStatus
  records_seen : Int
}

///|
pub fn InputReport::is_valid(self : InputReport) -> Bool {
  self.status == Complete && self.issues.is_empty()
}

///|
/// Return an independent array only when the entire input passed validation.
pub fn InputReport::validated_events(
  self : InputReport,
) -> Array[@model.Event]? {
  if self.is_valid() {
    Some(Array::from_iter(self.accepted_events.iter()))
  } else {
    None
  }
}

///|
fn make_report(
  accepted_events : Array[@model.Event],
  issues : Array[InputIssue],
  status : InputStatus,
  records_seen : Int,
) -> InputReport {
  {
    accepted_events: ReadOnlyArray::from_array(accepted_events),
    issues: ReadOnlyArray::from_array(issues),
    status,
    records_seen,
  }
}

///|
#deprecated
pub extend IssueKind with @debug.Debug::{to_repr}

///|
#deprecated
pub extend IssueKind with Eq::{equal, not_equal}

///|
#deprecated
pub extend InputIssue with @debug.Debug::{to_repr}

///|
#deprecated
pub extend InputIssue with Eq::{equal, not_equal}

///|
#deprecated
pub extend InputStatus with @debug.Debug::{to_repr}

///|
#deprecated
pub extend InputStatus with Eq::{equal, not_equal}
