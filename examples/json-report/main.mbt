///|
/// Environment-fed example; the production file-analysis CLI is a later step.
fn describe(text : String) -> @report.DiagnosticReport raise {
  let input = @input.parse_jsonl(text, source_path="report-example.jsonl") catch {
    error => return @report.from_failure(@report.InputConfiguration(error))
  }
  if !input.is_valid() {
    return @report.from_input(input)
  }
  let correlation = @correlate.correlate_input(input) catch {
    error => return @report.from_failure(@report.Correlation(error), input~)
  }
  let built = @constraints.build(correlation) catch {
    error => return @report.from_failure(@report.ConstraintBuild(error), input~)
  }
  let analysis = @solver.analyze(built) catch {
    error => return @report.from_failure(@report.Solver(error), input~)
  }
  @report.from_analysis(analysis, input~)
}

///|
fn main {
  let text = match @env.get_env_var("CHRONOLENS_REPORT_INPUT") {
    Some(text) => text
    None => abort("Set CHRONOLENS_REPORT_INPUT to this example's JSONL data.")
  }
  let diagnostic = describe(text) catch {
    error => abort("report construction failed: " + @debug.to_string(error))
  }
  match @env.get_env_var("CHRONOLENS_REPORT_FORMAT") {
    Some("markdown") => println(diagnostic.to_markdown())
    _ => println(diagnostic.stringify(pretty=true))
  }
}
