///|
/// Only a complete, valid input report may enter the correlation pipeline.
/// Invalid previews and truncated inputs raise InvalidInput.
pub fn correlate_input(
  report : @input.InputReport,
  max_events? : Int = 10000,
) -> CorrelationReport raise CorrelationError {
  if !report.is_valid() {
    raise InvalidInput
  }
  validate_limit(max_events, report.accepted_events.length())
  correlate(report.accepted_events, max_events~)
}
