///|
pub(all) suberror InputConfigError {
  InvalidLimit(String)
  InvalidSourcePath
} derive(Debug, Eq)

///|
pub struct InputLimits {
  max_input_bytes : Int
  max_line_bytes : Int
  max_records : Int
  max_clock_domains : Int
  max_field_bytes : Int
  max_issues : Int
  max_json_depth : Int
}

///|
/// Positive caps; sizes count UTF-8 bytes.
pub fn InputLimits::new(
  max_input_bytes? : Int = 8388608,
  max_line_bytes? : Int = 65536,
  max_records? : Int = 10000,
  max_clock_domains? : Int = 64,
  max_field_bytes? : Int = 4096,
  max_issues? : Int = 100,
  max_json_depth? : Int = 16,
) -> InputLimits raise InputConfigError {
  for
    (name, value) in [
      ("max_input_bytes", max_input_bytes),
      ("max_line_bytes", max_line_bytes),
      ("max_records", max_records),
      ("max_clock_domains", max_clock_domains),
      ("max_field_bytes", max_field_bytes),
      ("max_issues", max_issues),
      ("max_json_depth", max_json_depth),
    ] {
    if value <= 0 {
      raise InvalidLimit(name)
    }
  }
  if max_input_bytes > 67108864 {
    raise InvalidLimit("max_input_bytes")
  }
  if max_json_depth > 64 {
    raise InvalidLimit("max_json_depth")
  }
  {
    max_input_bytes,
    max_line_bytes,
    max_records,
    max_clock_domains,
    max_field_bytes,
    max_issues,
    max_json_depth,
  }
}

///|
pub impl Default for InputLimits with fn default() {
  {
    max_input_bytes: 8388608,
    max_line_bytes: 65536,
    max_records: 10000,
    max_clock_domains: 64,
    max_field_bytes: 4096,
    max_issues: 100,
    max_json_depth: 16,
  }
}

///|
pub extend InputLimits with Default::{default}

///|
#deprecated
pub extend InputConfigError with @debug.Debug::{to_repr}

///|
#deprecated
pub extend InputConfigError with Eq::{equal, not_equal}
