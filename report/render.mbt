///|
fn render_report(source : ReportSource) -> Json {
  let fields : Map[String, Json] = {
    "schema_version": Json::string("chronolens.diagnostic.v1"),
    "producer": Json::object({
      "module": Json::string("Mitsuha11zz/chronolens"),
      "version": Json::string("0.1.0"),
    }),
    "time_unit": Json::string("us"),
    "int64_encoding": Json::string("decimal_string"),
    "input": Json::null(),
    "coverage": Json::null(),
    "model": Json::null(),
    "summary": Json::null(),
    "has_conflicts": Json::null(),
    "events": Json::array([]),
    "messages": Json::array([]),
    "unresolved_groups": Json::array([]),
    "constraints": Json::array([]),
    "components": Json::array([]),
    "failure": Json::null(),
    "assumptions": string_array([
      "fixed_offsets_within_analysis_window", "only_explicit_unique_message_pairs_create_message_constraints",
      "relation_tolerance_and_priors_are_assumptions", "representative_offsets_are_not_utc",
      "components_have_independent_coordinates", "interval_endpoints_are_marginal",
      "negative_cycles_do_not_determine_root_cause",
    ]),
  }
  match source {
    InputOnly(input) => {
      fields["status"] = Json::string(input_status(input))
      fields["input"] = input_json(Some(input))
      fields["events"] = Json::array(
        sorted_events(input.accepted_events).iter().map(event_json).collect(),
      )
    }
    Failed(failure, input) => {
      let status = match input {
        Some(input) =>
          if input.is_valid() {
            "pipeline_failed"
          } else {
            input_status(input)
          }
        None => "pipeline_failed"
      }
      fields["status"] = Json::string(status)
      fields["input"] = input_json(input)
      fields["failure"] = pipeline_error_json(failure)
      if input is Some(input) {
        fields["events"] = Json::array(
          sorted_events(input.accepted_events).iter().map(event_json).collect(),
        )
      }
    }
    Analyzed(report, input) => {
      let (status, summary, has_conflicts) = analysis_summary(report.analysis)
      fields["status"] = Json::string(status)
      fields["has_conflicts"] = match has_conflicts {
        Some(value) => Json::boolean(value)
        None => Json::null()
      }
      fields["input"] = input_json(input)
      fields["summary"] = summary
      fields["coverage"] = coverage_json(report.input.correlation)
      fields["model"] = model_json(report.input)
      fields["events"] = Json::array(
        analysis_events(report).iter().map(event_json).collect(),
      )
      fields["messages"] = Json::array(
        report.input.correlation.pairs
        .iter()
        .map(pair => {
          Json::object({
            "key": key_json(pair.key),
            "send_event_id": Json::string(pair.send_event.event_id()),
            "receive_event_id": Json::string(pair.receive_event.event_id()),
          })
        })
        .collect(),
      )
      fields["unresolved_groups"] = Json::array(
        report.input.correlation.unresolved
        .iter()
        .map(unresolved_json)
        .collect(),
      )
      let constraints : Array[Json] = []
      for index, edge in report.input.constraints {
        constraints.push(constraint_json(index, edge))
      }
      fields["constraints"] = Json::array(constraints)
      fields["components"] = Json::array(
        report.analysis.components.iter().map(component_json).collect(),
      )
    }
  }
  Json::object(fields)
}
