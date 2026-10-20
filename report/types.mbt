///|
/// Typed pipeline failures are exported separately from feasibility verdicts.
pub(all) enum PipelineFailure {
  InputConfiguration(@input.InputConfigError)
  Correlation(@correlate.CorrelationError)
  ConstraintBuild(@constraints.ConstraintBuildError)
  Solver(@solver.SolveError)
} derive(Debug, Eq)

///|
pub(all) suberror ReportError {
  InvalidInputReport
  MismatchedInputEvents
} derive(Debug, Eq)

///|
priv enum ReportSource {
  InputOnly(@input.InputReport)
  Analyzed(@solver.AnalysisReport, @input.InputReport?)
  Failed(PipelineFailure, @input.InputReport?)
}

///|
/// Holds immutable source data. Each JSON export creates independent objects.
pub struct DiagnosticReport {
  priv source : ReportSource
}

///|
#deprecated
pub extend PipelineFailure with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PipelineFailure with Eq::{equal, not_equal}

///|
#deprecated
pub extend ReportError with @debug.Debug::{to_repr}

///|
#deprecated
pub extend ReportError with Eq::{equal, not_equal}
