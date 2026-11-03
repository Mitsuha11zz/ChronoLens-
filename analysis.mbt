///|
/// Options shared by the public JSONL analysis entry point.
pub(all) struct AnalysisOptions {
  /// JSONL input and resource limits.
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
/// Analyze ChronoLens JSONL text through parsing, message correlation,
/// constraint construction, solving, and diagnostic report creation.
///
/// Invalid JSONL is returned as an input diagnostic. A failure in a later
/// pipeline stage is returned as a failed diagnostic report. The function
/// raises only if the final report cannot be reconciled with its input report.
/// Defaults use zero relation tolerance and package resource limits.
pub fn analyze_jsonl(
  text : String,
  source_path~ : String = "<memory>",
  options~ : AnalysisOptions = AnalysisOptions::default(),
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
  let correlation = @correlate.correlate_input(parsed) catch {
    error =>
      return @report.from_failure(@report.Correlation(error), input=parsed)
  }
  let constraints = @constraints.build(
    correlation,
    relation_tolerance_us=options.relation_tolerance_us,
    max_constraints=options.solve_limits.max_constraints,
  ) catch {
    error =>
      return @report.from_failure(@report.ConstraintBuild(error), input=parsed)
  }
  let analysis = analyze_constraints(constraints, options) catch {
    error => return @report.from_failure(@report.Solver(error), input=parsed)
  }
  @report.from_analysis(analysis, input=parsed)
}
