///|
fn constraint_json(index : Int32, edge : @constraints.BuiltConstraint) -> Json {
  let constraint = edge.constraint
  Json::object({
    "index": Json(index),
    "left_clock": Json::string(constraint.left_clock()),
    "right_clock": Json::string(constraint.right_clock()),
    "upper_bound_us": Json::string(constraint.upper_bound_us().to_string()),
    "edge_from": Json::string(constraint.edge_from()),
    "edge_to": Json::string(constraint.edge_to()),
    "origin": origin_json(constraint.origin()),
    "evidence": match edge.evidence {
      @constraints.Message(pair~, tolerance_us~) =>
        Json::object({
          "kind": Json::string("message"),
          "key": key_json(pair.key),
          "send_event_id": Json::string(pair.send_event.event_id()),
          "receive_event_id": Json::string(pair.receive_event.event_id()),
          "relation_tolerance_us": Json::string(tolerance_us.to_string()),
        })
      @constraints.Prior(prior~, lower_bound~) =>
        Json::object({
          "kind": Json::string("prior"),
          "prior_label": Json::string(prior.label),
          "bound": Json::string(if lower_bound { "lower" } else { "upper" }),
        })
    },
  })
}

///|
fn model_json(input : @constraints.ConstraintSet) -> Json {
  let priors : Map[String, @constraints.OffsetPrior] = Map([])
  for edge in input.constraints {
    if edge.evidence is @constraints.Prior(prior~, ..) {
      priors[prior.label] = prior
    }
  }
  let labels = Array::from_iter(priors.keys())
  labels.sort_by((a, b) => a.lexical_compare(b))
  Json::object({
    "clock_model": Json::string("fixed_offset_per_clock_id"),
    "time_definition": Json::string("observed_timestamp_us + offset_us"),
    "constraint_definition": Json::string(
      "offset(left) - offset(right) <= upper_bound_us",
    ),
    "reference_scope": Json::string("weak_component"),
    "relation_tolerance_us": Json::string(
      input.relation_tolerance_us.to_string(),
    ),
    "priors": Json::array(
      labels.iter().map(label => prior_json(priors[label])).collect(),
    ),
    "resource_limits": Json::null(),
    "resource_limits_recording": Json::string("not_available_in_source_reports"),
  })
}
