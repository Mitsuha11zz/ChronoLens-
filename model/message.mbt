///|
#deprecated
pub extend EventKind with @debug.Debug::{to_repr}

///|
#deprecated
pub extend EventKind with Eq::{equal, not_equal}

///|
#deprecated
pub extend MessageKey with @debug.Debug::{to_repr}

///|
#deprecated
pub extend MessageKey with Eq::{equal, not_equal}

///|
#deprecated
pub extend MessageKey with Hash::{hash, hash_combine}

///|
/// Direction of a single, explicitly identified message event.
pub(all) enum EventKind {
  Send
  Receive
} derive(Debug, Eq)

///|
/// A message attempt is identified by all three fields.
pub struct MessageKey {
  trace_id : String
  message_id : String
  attempt : Int
} derive(Debug, Eq, Hash)

///|
/// Validate identifiers and retry index without normalizing identifier text.
pub fn MessageKey::new(
  trace_id~ : String,
  message_id~ : String,
  attempt~ : Int,
) -> MessageKey raise ModelError {
  require_identifier(trace_id, "trace_id")
  require_identifier(message_id, "message_id")
  if attempt < 0 {
    raise InvalidAttempt(attempt)
  }
  { trace_id, message_id, attempt, }
}

///|
pub fn MessageKey::trace_id(self : MessageKey) -> String {
  self.trace_id
}

///|
pub fn MessageKey::message_id(self : MessageKey) -> String {
  self.message_id
}

///|
pub fn MessageKey::attempt(self : MessageKey) -> Int {
  self.attempt
}
