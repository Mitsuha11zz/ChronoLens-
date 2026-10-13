///|
#deprecated
pub extend ConstraintOrigin with @debug.Debug::{to_repr}

///|
#deprecated
pub extend ConstraintOrigin with Eq::{equal, not_equal}

///|
#deprecated
pub extend DifferenceConstraint with @debug.Debug::{to_repr}

///|
#deprecated
pub extend DifferenceConstraint with Eq::{equal, not_equal}

///|
/// Evidence behind a constraint. Message references identify source events;
/// a prior label identifies a user-supplied assumption.
pub(all) enum ConstraintOrigin {
  Message(send_event_id~ : String, receive_event_id~ : String)
  Prior(label~ : String)
} derive(Debug, Eq)

///|
/// The inequality is offset(left_clock) - offset(right_clock) <= upper_bound_us.
/// Its graph edge goes from right_clock to left_clock.
pub struct DifferenceConstraint {
  left_clock : String
  right_clock : String
  upper_bound_us : Int64
  origin : ConstraintOrigin
} derive(Debug, Eq)

///|
/// Negative bounds and same-clock constraints are valid model inputs.
/// Feasibility is evaluated by the solver in a later stage.
pub fn DifferenceConstraint::new(
  left_clock~ : String,
  right_clock~ : String,
  upper_bound_us~ : Int64,
  origin~ : ConstraintOrigin,
) -> DifferenceConstraint raise ModelError {
  require_identifier(left_clock, "left_clock")
  require_identifier(right_clock, "right_clock")
  match origin {
    Message(send_event_id~, receive_event_id~) => {
      require_identifier(send_event_id, "origin.send_event_id")
      require_identifier(receive_event_id, "origin.receive_event_id")
    }
    Prior(label~) => require_identifier(label, "origin.label")
  }
  { left_clock, right_clock, upper_bound_us, origin, }
}

///|
pub fn DifferenceConstraint::left_clock(self : DifferenceConstraint) -> String {
  self.left_clock
}

///|
pub fn DifferenceConstraint::right_clock(self : DifferenceConstraint) -> String {
  self.right_clock
}

///|
pub fn DifferenceConstraint::upper_bound_us(
  self : DifferenceConstraint,
) -> Int64 {
  self.upper_bound_us
}

///|
pub fn DifferenceConstraint::origin(
  self : DifferenceConstraint,
) -> ConstraintOrigin {
  self.origin
}

///|
pub fn DifferenceConstraint::edge_from(self : DifferenceConstraint) -> String {
  self.right_clock
}

///|
pub fn DifferenceConstraint::edge_to(self : DifferenceConstraint) -> String {
  self.left_clock
}
