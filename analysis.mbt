///|
/// Options shared by the public JSONL and typed-event analysis entry points.
pub(all) struct AnalysisOptions {
  /// JSONL limits; max_records also caps typed-event collection size.
  input_limits : @input.InputLimits
  /// Extra tolerance for each send-before-receive relation, in microseconds.
  relation_tolerance_us : Int64
  /// Optional reference clock for offset coordinates.
  reference_clock : String?
  /// Solver resource limits.
  solve_limits : @solver.SolveLimits
}

///|
pub impl Default for AnalysisOptions with fn default() -> AnalysisOptions {
  {
    input_limits: @input.InputLimits::default(),
    relation_tolerance_us: 0L,
    reference_clock: None,
    solve_limits: @solver.SolveLimits::default(),
  }
}

///|
pub extend AnalysisOptions with Default::{default}

///|
fn analyze_constraints(
  constraints : @constraints.ConstraintSet,
  options : AnalysisOptions,
) -> @solver.AnalysisReport raise @solver.SolveError {
  match options.reference_clock {
    Some(reference_clock) =>
      @solver.analyze(
        constraints,
        reference_clock~,
        limits=options.solve_limits,
      )
    None => @solver.analyze(constraints, limits=options.solve_limits)
  }
}

///|
fn max_correlation_events(options : AnalysisOptions) -> Int32 {
  if options.input_limits.max_records > 1000000 {
    1000000
  } else {
    options.input_limits.max_records
  }
}

///|
fn analyze_correlation(
  correlation : @correlate.CorrelationReport,
  options : AnalysisOptions,
  priors : ArrayView[@constraints.OffsetPrior],
  input? : @input.InputReport,
) -> @report.DiagnosticReport raise @report.ReportError {
  let constraints = @constraints.build(
    correlation,
    relation_tolerance_us=options.relation_tolerance_us,
    priors~,
    max_constraints=options.solve_limits.max_constraints,
  ) catch {
    error => return @report.from_failure(@report.ConstraintBuild(error), input?)
  }
  let analysis = analyze_constraints(constraints, options) catch {
    error => return @report.from_failure(@report.Solver(error), input?)
  }
  @report.from_analysis(analysis, input?)
}

///|
/// Analyze ChronoLens JSONL text through parsing, message correlation,
/// constraint construction, solving, and diagnostic report creation.
///
/// Invalid JSONL is returned as an input diagnostic. A failure in a later
/// pipeline stage is returned as a failed diagnostic report. The function
/// raises only if the final report cannot be reconciled with its input report.
/// Defaults use zero relation tolerance and package resource limits. The
/// effective correlation event limit is capped at one million.
pub fn analyze_jsonl(
  text : String,
  source_path~ : String = "<memory>",
  options~ : AnalysisOptions = AnalysisOptions::default(),
  priors~ : ArrayView[@constraints.OffsetPrior] = [],
) -> @report.DiagnosticReport raise @report.ReportError {
  let parsed = @input.parse_jsonl(
    text,
    source_path~,
    limits=options.input_limits,
  ) catch {
    error => return @report.from_failure(@report.InputConfiguration(error))
  }
  if !parsed.is_valid() {
    return @report.from_input(parsed)
  }
  let correlation = @correlate.correlate_input(
    parsed,
    max_events=max_correlation_events(options),
  ) catch {
    error =>
      return @report.from_failure(@report.Correlation(error), input=parsed)
  }
  analyze_correlation(correlation, options, priors, input=parsed)
}

///|
/// Analyze already-constructed events without converting them to JSONL first.
///
/// Correlation and later-stage failures are returned in a diagnostic report.
/// Since no parser ran, the report's input section is null. The event count is
/// limited by `options.input_limits.max_records` and the correlation package's
/// hard limit. Duplicate event IDs and unresolved message groups remain
/// explicit diagnostics.
pub fn analyze_events(
  events : ArrayView[@model.Event],
  options~ : AnalysisOptions = AnalysisOptions::default(),
  priors~ : ArrayView[@constraints.OffsetPrior] = [],
) -> @report.DiagnosticReport raise @report.ReportError {
  let correlation = @correlate.correlate(
    events,
    max_events=max_correlation_events(options),
  ) catch {
    error => return @report.from_failure(@report.Correlation(error))
  }
  analyze_correlation(correlation, options, priors)
}
