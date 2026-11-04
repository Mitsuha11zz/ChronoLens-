///|
#derive(Debug, Eq)
pub(all) suberror CorrelationError {
  InvalidInput
  InvalidEventLimit
  EventLimitExceeded(limit~ : Int, count~ : Int)
  DuplicateEventId(String)
}

///|
#deprecated
pub extend CorrelationError with @debug.Debug::{to_repr}

///|
#deprecated
pub extend CorrelationError with Eq::{equal, not_equal}
