///|
/// Export parser diagnostics and accepted-event previews without analysis.
pub fn from_input(input : @input.InputReport) -> DiagnosticReport {
  { source: InputOnly(input), }
}

///|
/// Optional parser evidence must be valid and contain exactly the same events,
/// including timestamps and source locations. No parser verdict is invented
/// when callers analyze typed events directly.
pub fn from_analysis(
  analysis : @solver.AnalysisReport,
  input? : @input.InputReport,
) -> DiagnosticReport raise ReportError {
  if input is Some(parsed) {
    if !parsed.is_valid() {
      raise InvalidInputReport
    }
    let events = analysis_events(analysis)
    if events.length() != parsed.accepted_events.length() {
      raise MismatchedInputEvents
    }
    let by_id : Map[String, @model.Event] = Map([])
    for event in events {
      by_id[event.event_id()] = event
    }
    for event in parsed.accepted_events {
      match by_id.get(event.event_id()) {
        Some(expected) => if expected != event { raise MismatchedInputEvents }
        None => raise MismatchedInputEvents
      }
    }
  }
  { source: Analyzed(analysis, input), }
}

///|
/// Preserve a failed pipeline stage without fabricating a partial solution.
/// The caller supplies the actual raised error and any available parser report.
pub fn from_failure(
  failure : PipelineFailure,
  input? : @input.InputReport,
) -> DiagnosticReport {
  { source: Failed(failure, input), }
}

///|
/// Export schema chronolens.diagnostic.v1. All Int64 values are strings.
pub fn DiagnosticReport::to_json(self : DiagnosticReport) -> Json {
  render_report(self.source)
}

///|
/// Deterministic key order, optional two-space indentation, no wall-clock stamp.
pub fn DiagnosticReport::stringify(
  self : DiagnosticReport,
  pretty~ : Bool = false,
) -> String {
  let builder = StringBuilder()
  write_canonical(self.to_json(), builder, if pretty { 2 } else { 0 }, 0)
  builder.to_string()
}
