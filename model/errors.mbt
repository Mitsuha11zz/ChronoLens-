///|
#deprecated
pub extend ModelError with @debug.Debug::{to_repr}

///|
#deprecated
pub extend ModelError with Eq::{equal, not_equal}

///|
/// Invalid data supplied to a model constructor.
pub(all) suberror ModelError {
  EmptyIdentifier(String)
  InvalidAttempt(Int)
  InvalidSourceLine(Int)
} derive(Debug, Eq)

///|
fn require_identifier(value : String, field : String) -> Unit raise ModelError {
  if value.trim().is_empty() {
    raise EmptyIdentifier(field)
  }
}
