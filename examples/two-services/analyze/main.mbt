///|
/// Bounded data bridge for this sample, not the planned file-analysis CLI.
fn bound_text(bound : @solver.OffsetBound) -> String {
  match bound {
    @solver.Finite(value) => value.to_string()
    @solver.Unbounded => "unbounded"
  }
}

///|
fn analyze_capture(text : String) -> Unit raise {
  let parsed = @input.parse_jsonl(text, source_path="local-rpc.capture.jsonl")
  let paired = @correlate.correlate_input(parsed)
  if !paired.fully_paired() {
    abort("capture contains missing or ambiguous message identities")
  }
  let report = @solver.analyze(@constraints.build(paired), reference_clock="A")
  let analysis = report.analysis
  println(
    "CAPTURE records=\{parsed.records_seen} pairs=\{paired.pairs.length()} clocks=\{analysis.clocks.length()} components=\{analysis.components.length()}",
  )
  for component in analysis.components {
    match component.outcome {
      @solver.ComponentFeasible(offsets~, intervals~) =>
        for i, interval in intervals {
          println(
            "RESULT clock=\{interval.clock_id} lower_us=\{bound_text(interval.lower)} upper_us=\{bound_text(interval.upper)} representative_us=\{offsets[i].offset_us}",
          )
        }
      @solver.ComponentInfeasible(cycle~) =>
        abort("capture is inconsistent: " + @debug.to_string(cycle))
      @solver.ComponentFailed(error~) =>
        abort("capture analysis did not complete: " + @debug.to_string(error))
    }
  }
}

///|
fn main {
  let text = match @env.get_env_var("CHRONOLENS_SAMPLE_INPUT") {
    Some(text) => text
    None => abort("Use examples/two-services/run.py --analyze or --replay.")
  }
  analyze_capture(text) catch {
    error => abort("capture input rejected: " + @debug.to_string(error))
  }
}
