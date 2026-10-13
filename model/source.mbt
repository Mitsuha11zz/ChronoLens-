///|
#deprecated
pub extend SourceLocation with @debug.Debug::{to_repr}

///|
#deprecated
pub extend SourceLocation with Eq::{equal, not_equal}

///|
/// Optional evidence location; line numbers are one-based.
pub struct SourceLocation {
  path : String
  line : Int
} derive(Debug, Eq)

///|
pub fn SourceLocation::new(
  path~ : String,
  line~ : Int,
) -> SourceLocation raise ModelError {
  require_identifier(path, "source.path")
  if line < 1 {
    raise InvalidSourceLine(line)
  }
  { path, line, }
}

///|
pub fn SourceLocation::path(self : SourceLocation) -> String {
  self.path
}

///|
pub fn SourceLocation::line(self : SourceLocation) -> Int {
  self.line
}
