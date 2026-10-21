///|
/// Render the same diagnostic data as a readable Markdown report.
pub fn DiagnosticReport::to_markdown(self : DiagnosticReport) -> String {
  markdown_report(self.to_json())
}

///|
fn markdown_report(report : Json) -> String {
  let builder = StringBuilder()
  builder.write_string("# ChronoLens diagnostic report\n\n")
  markdown_bullet(
    builder,
    "Status",
    markdown_field(report, "status", "unknown"),
  )
  let conflicts = markdown_field(report, "has_conflicts", "null")
  markdown_bullet(
    builder,
    "Conflicts",
    if conflicts == "true" {
      "yes"
    } else if conflicts == "false" {
      "no"
    } else {
      "unknown"
    },
  )
  markdown_bullet(builder, "Schema", "chronolens.diagnostic.v1")
  markdown_write_summary(builder, report)
  markdown_write_input(builder, report)
  markdown_write_coverage(builder, report)
  markdown_write_model(builder, report)
  markdown_write_messages(builder, report)
  markdown_write_unresolved(builder, report)
  markdown_write_events(builder, report)
  markdown_write_components(builder, report)
  markdown_write_failure(builder, report)
  markdown_write_assumptions(builder, report)
  builder.to_string()
}

///|
fn markdown_bullet(
  builder : StringBuilder,
  label : String,
  value : String,
) -> Unit {
  builder.write_string("- ")
  builder.write_string(label)
  builder.write_string(": ")
  builder.write_string(markdown_code(value))
  builder.write_char('\n')
}

///|
fn markdown_member(value : Json, key : String) -> Json? {
  match value {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn markdown_value_text(value : Json) -> String {
  match value {
    String(text) => text
    _ => markdown_compact_json(value)
  }
}

///|
fn markdown_field(value : Json, key : String, fallback : String) -> String {
  match markdown_member(value, key) {
    Some(item) => markdown_value_text(item)
    None => fallback
  }
}

///|
fn markdown_optional(value : Json?) -> String {
  match value {
    None => "—"
    Some(Null) => "—"
    Some(item) => markdown_value_text(item)
  }
}

///|
fn markdown_array(value : Json, key : String) -> Array[Json] {
  match markdown_member(value, key) {
    Some(Array(items)) => Array::from_iter(items.iter())
    _ => []
  }
}

///|
fn markdown_compact_json(value : Json) -> String {
  let builder = StringBuilder()
  write_canonical(value, builder, 0, 0)
  builder.to_string()
}

///|
/// Put untrusted values in an HTML code span and escape HTML-sensitive text.
/// Entities keep table delimiters and line breaks from changing Markdown structure.
fn markdown_code(value : String) -> String {
  let builder = StringBuilder()
  builder.write_string("<code>")
  for character in value.to_array() {
    match character {
      '&' => builder.write_string("&amp;")
      '<' => builder.write_string("&lt;")
      '>' => builder.write_string("&gt;")
      '|' => builder.write_string("&#124;")
      '\n' => builder.write_string("&#10;")
      '\r' => builder.write_string("&#13;")
      '\t' => builder.write_string("&#9;")
      _ => builder.write_char(character)
    }
  }
  builder.write_string("</code>")
  builder.to_string()
}

///|
fn markdown_write_row(
  builder : StringBuilder,
  cells : ArrayView[String],
) -> Unit {
  builder.write_char('|')
  for cell in cells {
    builder.write_char(' ')
    builder.write_string(markdown_code(cell))
    builder.write_string(" |")
  }
  builder.write_char('\n')
}

///|
fn markdown_write_header(
  builder : StringBuilder,
  labels : ArrayView[String],
) -> Unit {
  builder.write_char('|')
  for label in labels {
    builder.write_char(' ')
    builder.write_string(label)
    builder.write_string(" |")
  }
  builder.write_char('\n')
  builder.write_char('|')
  for _ in labels {
    builder.write_string(" --- |")
  }
  builder.write_char('\n')
}

///|
fn markdown_write_summary(builder : StringBuilder, report : Json) -> Unit {
  match markdown_member(report, "summary") {
    None | Some(Null) =>
      builder.write_string(
        "\n## Summary\n\nNo analysis summary is available.\n",
      )
    Some(summary) => {
      builder.write_string("\n## Summary\n\n")
      let stats = markdown_member(summary, "stats")
      let rows : Array[Array[String]] = [
        ["Components", markdown_field(summary, "component_count", "0")],
        [
          "Feasible components",
          markdown_field(summary, "feasible_components", "0"),
        ],
        [
          "Infeasible components",
          markdown_field(summary, "infeasible_components", "0"),
        ],
        ["Failed components", markdown_field(summary, "failed_components", "0")],
        [
          "Clocks with an unbounded interval side",
          markdown_field(summary, "unbounded_clock_count", "0"),
        ],
        ["Clocks", markdown_nested_field(stats, "clock_count", "0")],
        ["Constraints", markdown_nested_field(stats, "constraint_count", "0")],
        ["Relaxation passes", markdown_nested_field(stats, "passes", "0")],
        ["Edge visits", markdown_nested_field(stats, "edge_visits", "0")],
      ]
      markdown_write_header(builder, ["Measure", "Value"])
      for row in rows {
        markdown_write_row(builder, row)
      }
    }
  }
}

///|
fn markdown_nested_field(
  value : Json?,
  key : String,
  fallback : String,
) -> String {
  match value {
    Some(object) => markdown_field(object, key, fallback)
    None => fallback
  }
}

///|
fn markdown_write_input(builder : StringBuilder, report : Json) -> Unit {
  builder.write_string("\n## Input validation\n\n")
  match markdown_member(report, "input") {
    None | Some(Null) =>
      builder.write_string("No parser report was attached.\n")
    Some(input) => {
      let rows : Array[Array[String]] = [
        ["Validation", markdown_field(input, "validation", "unknown")],
        ["Scan status", markdown_field(input, "scan_status", "unknown")],
        ["Limited by", markdown_optional(markdown_member(input, "limited_by"))],
        ["Records seen", markdown_field(input, "records_seen", "0")],
        ["Accepted events", markdown_field(input, "accepted_event_count", "0")],
        [
          "Accepted events are a preview",
          markdown_field(input, "events_are_preview", "false"),
        ],
      ]
      markdown_write_header(builder, ["Measure", "Value"])
      for row in rows {
        markdown_write_row(builder, row)
      }
      let issues = markdown_array(input, "issues")
      builder.write_string("\n### Input issues\n\n")
      if issues.is_empty() {
        builder.write_string("No parser issues were reported.\n")
      } else {
        markdown_write_header(builder, ["Line", "Code", "Details"])
        for issue in issues {
          markdown_write_row(builder, [
            markdown_optional(markdown_member(issue, "line")),
            markdown_field(issue, "code", "unknown"),
            markdown_optional(markdown_member(issue, "details")),
          ])
        }
      }
    }
  }
}

///|
fn markdown_write_coverage(builder : StringBuilder, report : Json) -> Unit {
  builder.write_string("\n## Message coverage\n\n")
  match markdown_member(report, "coverage") {
    None | Some(Null) =>
      builder.write_string("Message correlation was not run.\n")
    Some(coverage) => {
      markdown_write_header(builder, ["Measure", "Value"])
      let rows : Array[Array[String]] = [
        ["Events", markdown_field(coverage, "total_events", "0")],
        ["Message groups", markdown_field(coverage, "group_count", "0")],
        ["Paired groups", markdown_field(coverage, "paired_groups", "0")],
        [
          "Unresolved groups",
          markdown_field(coverage, "unresolved_groups", "0"),
        ],
        [
          "Groups missing a send",
          markdown_field(coverage, "missing_groups", "0"),
        ],
        ["Ambiguous groups", markdown_field(coverage, "ambiguous_groups", "0")],
        [
          "Pairing status",
          markdown_field(coverage, "pairing_status", "unknown"),
        ],
        [
          "Log completeness",
          markdown_field(coverage, "log_completeness", "unknown"),
        ],
      ]
      for row in rows {
        markdown_write_row(builder, row)
      }
      builder.write_string(
        "\nMissing-send and ambiguous counts can overlap. Pairing success does not establish log completeness.\n",
      )
    }
  }
}

///|
fn markdown_write_model(builder : StringBuilder, report : Json) -> Unit {
  match markdown_member(report, "model") {
    None | Some(Null) => ()
    Some(model) => {
      builder.write_string("\n## Clock model and assumptions\n\n")
      markdown_write_header(builder, ["Setting", "Value"])
      let rows : Array[Array[String]] = [
        ["Clock model", markdown_field(model, "clock_model", "unknown")],
        ["Time definition", markdown_field(model, "time_definition", "unknown")],
        [
          "Constraint definition",
          markdown_field(model, "constraint_definition", "unknown"),
        ],
        ["Reference scope", markdown_field(model, "reference_scope", "unknown")],
        [
          "Relation tolerance (µs)",
          markdown_field(model, "relation_tolerance_us", "unknown"),
        ],
        [
          "Resource limits",
          markdown_optional(markdown_member(model, "resource_limits")),
        ],
        [
          "Resource limit recording",
          markdown_field(model, "resource_limits_recording", "unknown"),
        ],
      ]
      for row in rows {
        markdown_write_row(builder, row)
      }
      let priors = markdown_array(model, "priors")
      builder.write_string("\n### Offset priors\n\n")
      if priors.is_empty() {
        builder.write_string("No offset priors were supplied.\n")
      } else {
        markdown_write_header(builder, [
          "Label", "Clock", "Reference", "Lower (µs)", "Upper (µs)",
        ])
        for prior in priors {
          markdown_write_row(builder, [
            markdown_field(prior, "label", ""),
            markdown_field(prior, "clock_id", ""),
            markdown_field(prior, "reference_clock", ""),
            markdown_optional(markdown_member(prior, "lower_us")),
            markdown_optional(markdown_member(prior, "upper_us")),
          ])
        }
      }
    }
  }
}

///|
fn markdown_write_messages(builder : StringBuilder, report : Json) -> Unit {
  let messages = markdown_array(report, "messages")
  builder.write_string("\n## Paired messages\n\n")
  if messages.is_empty() {
    builder.write_string("No uniquely paired messages were found.\n")
  } else {
    markdown_write_header(builder, ["Key", "Send event", "Receive event"])
    for message in messages {
      markdown_write_row(builder, [
        markdown_optional(markdown_member(message, "key")),
        markdown_field(message, "send_event_id", ""),
        markdown_field(message, "receive_event_id", ""),
      ])
    }
  }
}

///|
fn markdown_join(values : Array[Json], separator : String) -> String {
  let builder = StringBuilder()
  for index, value in values {
    if index > 0 {
      builder.write_string(separator)
    }
    builder.write_string(markdown_value_text(value))
  }
  builder.to_string()
}

///|
fn markdown_write_unresolved(builder : StringBuilder, report : Json) -> Unit {
  let groups = markdown_array(report, "unresolved_groups")
  builder.write_string("\n## Unresolved message groups\n\n")
  if groups.is_empty() {
    builder.write_string("No unresolved groups were reported.\n")
  } else {
    markdown_write_header(builder, [
      "Key", "Issues", "Send events", "Receive events",
    ])
    for group in groups {
      markdown_write_row(builder, [
        markdown_optional(markdown_member(group, "key")),
        markdown_join(markdown_array(group, "issues"), ", "),
        markdown_join(markdown_array(group, "send_event_ids"), ", "),
        markdown_join(markdown_array(group, "receive_event_ids"), ", "),
      ])
    }
  }
}

///|
fn markdown_write_events(builder : StringBuilder, report : Json) -> Unit {
  let events = markdown_array(report, "events")
  builder.write_string("\n## Events\n\n")
  if events.is_empty() {
    builder.write_string("No events are available.\n")
  } else {
    markdown_write_header(builder, [
      "Event", "Clock", "Kind", "Timestamp (µs)", "Message key", "Source",
    ])
    for event in events {
      let key = markdown_field(event, "trace_id", "") +
        "/" +
        markdown_field(event, "message_id", "") +
        "/" +
        markdown_field(event, "attempt", "0")
      let source = match markdown_member(event, "source") {
        None | Some(Null) => "—"
        Some(location) =>
          markdown_field(location, "path", "") +
          ":" +
          markdown_field(location, "line", "?")
      }
      markdown_write_row(builder, [
        markdown_field(event, "event_id", ""),
        markdown_field(event, "clock_id", ""),
        markdown_field(event, "kind", ""),
        markdown_field(event, "ts_us", ""),
        key,
        source,
      ])
    }
  }
}

///|
fn markdown_write_components(builder : StringBuilder, report : Json) -> Unit {
  let components = markdown_array(report, "components")
  let constraints = markdown_array(report, "constraints")
  builder.write_string("\n## Clock components\n")
  if components.is_empty() {
    builder.write_string("\nNo component results are available.\n")
  } else {
    for component in components {
      markdown_write_component(builder, component, constraints)
    }
  }
}

///|
fn markdown_write_component(
  builder : StringBuilder,
  component : Json,
  constraints : Array[Json],
) -> Unit {
  let id = markdown_field(component, "component_id", "?")
  let status = markdown_field(component, "status", "unknown")
  builder.write_string("\n### Component ")
  builder.write_string(markdown_code(id))
  builder.write_string(": ")
  builder.write_string(markdown_code(status))
  builder.write_string("\n\n")
  markdown_bullet(
    builder,
    "Clocks",
    markdown_join(markdown_array(component, "clock_ids"), ", "),
  )
  markdown_bullet(
    builder,
    "Reference clock",
    markdown_field(component, "reference_clock", ""),
  )
  markdown_bullet(
    builder,
    "Constraint indices",
    markdown_join(markdown_array(component, "constraint_indices"), ", "),
  )
  let stats = markdown_member(component, "stats")
  markdown_bullet(
    builder,
    "Edge visits",
    markdown_nested_field(stats, "edge_visits", "0"),
  )
  match status {
    "feasible" => markdown_write_feasible_component(builder, component)
    "infeasible" => markdown_write_cycle(builder, component, constraints)
    "failed" => markdown_write_component_error(builder, component)
    _ => ()
  }
}

///|
fn markdown_find_clock_value(
  values : Array[Json],
  key : String,
  clock : String,
) -> String {
  for value in values {
    if markdown_field(value, "clock_id", "") == clock {
      return markdown_field(value, key, "—")
    }
  }
  "—"
}

///|
fn markdown_bound(value : Json?, side : String) -> String {
  match value {
    Some(bound) =>
      if markdown_field(bound, "kind", "") == "unbounded" {
        if side == "lower" {
          "−∞"
        } else {
          "+∞"
        }
      } else if markdown_field(bound, "kind", "") == "finite" {
        markdown_field(bound, "value_us", "?") + " µs"
      } else {
        "unknown"
      }
    None => "unknown"
  }
}

///|
fn markdown_write_feasible_component(
  builder : StringBuilder,
  component : Json,
) -> Unit {
  let offsets = markdown_array(component, "offsets")
  let intervals = markdown_array(component, "intervals")
  builder.write_string(
    "\nRepresentative offsets use the component reference clock as zero; they are not UTC.\n\n",
  )
  markdown_write_header(builder, [
    "Clock", "Representative offset (µs)", "Lower bound", "Upper bound",
  ])
  for interval in intervals {
    let clock = markdown_field(interval, "clock_id", "")
    markdown_write_row(builder, [
      clock,
      markdown_find_clock_value(offsets, "offset_us", clock),
      markdown_bound(markdown_member(interval, "lower"), "lower"),
      markdown_bound(markdown_member(interval, "upper"), "upper"),
    ])
  }
  builder.write_string(
    "\nBounds are marginal: separate endpoints are not guaranteed to be jointly attainable.\n",
  )
}

///|
fn markdown_find_constraint(
  constraints : Array[Json],
  wanted_index : String,
) -> Json? {
  for constraint in constraints {
    if markdown_field(constraint, "index", "") == wanted_index {
      return Some(constraint)
    }
  }
  None
}

///|
fn markdown_constraint_text(constraint : Json) -> String {
  "offset(" +
  markdown_field(constraint, "left_clock", "?") +
  ") - offset(" +
  markdown_field(constraint, "right_clock", "?") +
  ") <= " +
  markdown_field(constraint, "upper_bound_us", "?") +
  " µs"
}

///|
fn markdown_evidence_text(constraint : Json) -> String {
  match markdown_member(constraint, "evidence") {
    Some(evidence) =>
      if markdown_field(evidence, "kind", "") == "message" {
        "message send=" +
        markdown_field(evidence, "send_event_id", "?") +
        " receive=" +
        markdown_field(evidence, "receive_event_id", "?") +
        " tolerance=" +
        markdown_field(evidence, "relation_tolerance_us", "?") +
        " µs"
      } else {
        "prior " +
        markdown_field(evidence, "prior_label", "?") +
        " " +
        markdown_field(evidence, "bound", "?") +
        " bound"
      }
    None => "unknown evidence"
  }
}

///|
fn markdown_write_cycle(
  builder : StringBuilder,
  component : Json,
  constraints : Array[Json],
) -> Unit {
  let cycle = markdown_member(component, "cycle")
  match cycle {
    None | Some(Null) =>
      builder.write_string("\nNo cycle details are available.\n")
    Some(cycle) => {
      builder.write_string("\nNegative cycle total weight: ")
      builder.write_string(
        markdown_code(markdown_field(cycle, "total_weight_us", "?")),
      )
      builder.write_string(" µs.\n\n")
      builder.write_string(
        "The cycle proves these constraints are incompatible; it does not identify a root cause or promise a minimum conflict set.\n\n",
      )
      let indices = markdown_array(cycle, "constraint_indices")
      markdown_write_header(builder, [
        "Constraint", "Inequality", "Graph edge", "Evidence",
      ])
      for index in indices {
        let wanted_index = markdown_value_text(index)
        match markdown_find_constraint(constraints, wanted_index) {
          None =>
            markdown_write_row(builder, [
              wanted_index, "missing from report", "—", "—",
            ])
          Some(constraint) =>
            markdown_write_row(builder, [
              wanted_index,
              markdown_constraint_text(constraint),
              markdown_field(constraint, "edge_from", "?") +
              " → " +
              markdown_field(constraint, "edge_to", "?"),
              markdown_evidence_text(constraint),
            ])
        }
      }
    }
  }
}

///|
fn markdown_write_component_error(
  builder : StringBuilder,
  component : Json,
) -> Unit {
  match markdown_member(component, "error") {
    None | Some(Null) =>
      builder.write_string("\nNo component error details are available.\n")
    Some(error) => {
      builder.write_string("\nComponent calculation failed: ")
      builder.write_string(
        markdown_code(markdown_field(error, "code", "unknown")),
      )
      builder.write_string("\n\nDetails: ")
      let details = match markdown_member(error, "details") {
        Some(value) => value
        None => Json::null()
      }
      builder.write_string(markdown_code(markdown_compact_json(details)))
      builder.write_char('\n')
    }
  }
}

///|
fn markdown_write_failure(builder : StringBuilder, report : Json) -> Unit {
  match markdown_member(report, "failure") {
    None | Some(Null) => ()
    Some(failure) => {
      builder.write_string("\n## Pipeline failure\n\n")
      markdown_bullet(
        builder,
        "Stage",
        markdown_field(failure, "stage", "unknown"),
      )
      match markdown_member(failure, "error") {
        None | Some(Null) => ()
        Some(error) => {
          markdown_bullet(
            builder,
            "Code",
            markdown_field(error, "code", "unknown"),
          )
          markdown_bullet(
            builder,
            "Details",
            markdown_compact_json(
              match markdown_member(error, "details") {
                Some(details) => details
                None => Json::null()
              },
            ),
          )
        }
      }
    }
  }
}

///|
fn markdown_assumption(code : String) -> String {
  match code {
    "fixed_offsets_within_analysis_window" =>
      "Each clock has one fixed offset during the analyzed window."
    "only_explicit_unique_message_pairs_create_message_constraints" =>
      "Only uniquely matched send and receive pairs create message constraints."
    "relation_tolerance_and_priors_are_assumptions" =>
      "Message relation tolerance and offset priors are assumptions."
    "representative_offsets_are_not_utc" =>
      "Representative offsets use a reference coordinate; they are not UTC."
    "components_have_independent_coordinates" =>
      "Disconnected components have independent reference coordinates."
    "interval_endpoints_are_marginal" =>
      "Interval endpoints are marginal and may not be jointly attainable."
    "negative_cycles_do_not_determine_root_cause" =>
      "A negative cycle proves incompatible constraints but does not identify a root cause."
    _ => code
  }
}

///|
fn markdown_write_assumptions(builder : StringBuilder, report : Json) -> Unit {
  let assumptions = markdown_array(report, "assumptions")
  builder.write_string("\n## Interpretation and model assumptions\n")
  let no_model = match markdown_member(report, "model") {
    None | Some(Null) => true
    Some(_) => false
  }
  if no_model {
    builder.write_string(
      "\nThese are ChronoLens model conventions; no constraint analysis was available for this report.\n",
    )
  }
  if assumptions.is_empty() {
    builder.write_string("\nNo assumptions were listed.\n")
  } else {
    builder.write_char('\n')
    for assumption in assumptions {
      builder.write_string("- ")
      builder.write_string(markdown_assumption(markdown_value_text(assumption)))
      builder.write_char('\n')
    }
  }
}
