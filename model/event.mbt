///|
#deprecated
pub extend Event with @debug.Debug::{to_repr}

///|
#deprecated
pub extend Event with Eq::{equal, not_equal}

///|
/// An immutable observation. Timestamp units are signed integer microseconds.
/// Event-id uniqueness is a dataset-level responsibility.
pub struct Event {
  event_id : String
  clock_id : String
  key : MessageKey
  kind : EventKind
  timestamp_us : Int64
  source : SourceLocation?
} derive(Debug, Eq)

///|
/// Create an observation without changing its timestamp or identifier text.
/// Negative timestamps are valid; timestamp arithmetic belongs to later stages.
pub fn Event::new(
  event_id~ : String,
  clock_id~ : String,
  key~ : MessageKey,
  kind~ : EventKind,
  timestamp_us~ : Int64,
  source? : SourceLocation,
) -> Event raise ModelError {
  require_identifier(event_id, "event_id")
  require_identifier(clock_id, "clock_id")
  { event_id, clock_id, key, kind, timestamp_us, source, }
}

///|
pub fn Event::event_id(self : Event) -> String {
  self.event_id
}

///|
pub fn Event::clock_id(self : Event) -> String {
  self.clock_id
}

///|
pub fn Event::key(self : Event) -> MessageKey {
  self.key
}

///|
pub fn Event::kind(self : Event) -> EventKind {
  self.kind
}

///|
pub fn Event::timestamp_us(self : Event) -> Int64 {
  self.timestamp_us
}

///|
pub fn Event::source(self : Event) -> SourceLocation? {
  self.source
}
