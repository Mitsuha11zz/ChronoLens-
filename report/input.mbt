///|
fn issue_json(issue : @input.InputIssue) -> Json {
  let details : Map[String, Json] = Map([])
  let code = match issue.kind {
    @input.InvalidJson => "invalid_json"
    @input.ExpectedObject => "expected_object"
    @input.EmptyInput => "empty_input"
    @input.MissingField(field) => {
      details["field"] = Json::string(field)
      "missing_field"
    }
    @input.WrongType(field) => {
      details["field"] = Json::string(field)
      "wrong_type"
    }
    @input.UnknownField(field) => {
      details["field"] = Json::string(field)
      "unknown_field"
    }
    @input.DuplicateField(field) => {
      details["field"] = Json::string(field)
      "duplicate_field"
    }
    @input.InvalidValue(field) => {
      details["field"] = Json::string(field)
      "invalid_value"
    }
    @input.DuplicateEventId(first_line~) => {
      details["first_line"] = Json(first_line)
      "duplicate_event_id"
    }
    @input.LimitExceeded(limit) => {
      details["limit"] = Json::string(limit)
      "limit_exceeded"
    }
  }
  Json::object({
    "code": Json::string(code),
    "line": match issue.line {
      None => Json::null()
      Some(line) => Json(line)
    },
    "details": Json::object(details),
  })
}

///|
fn input_json(input : @input.InputReport?) -> Json {
  match input {
    None => Json::null()
    Some(input) =>
      Json::object({
        "validation": Json::string(
          if input.is_valid() {
            "valid"
          } else {
            "invalid"
          },
        ),
        "scan_status": Json::string(
          match input.status {
            @input.Complete => "complete"
            @input.Limited(_) => "limited"
          },
        ),
        "limited_by": match input.status {
          @input.Complete => Json::null()
          @input.Limited(limit) => Json::string(limit)
        },
        "records_seen": Json(input.records_seen),
        "accepted_event_count": Json(input.accepted_events.length()),
        "events_are_preview": Json::boolean(!input.is_valid()),
        "issues": Json::array(input.issues.iter().map(issue_json).collect()),
      })
  }
}

///|
fn input_status(input : @input.InputReport) -> String {
  match input.status {
    @input.Limited(_) => "input_limited"
    @input.Complete =>
      if input.is_valid() {
        "not_analyzed"
      } else {
        "input_invalid"
      }
  }
}

///|
fn coverage_json(report : @correlate.CorrelationReport) -> Json {
  let stats = report.stats
  Json::object({
    "total_events": Json(stats.total_events),
    "group_count": Json(stats.group_count),
    "paired_groups": Json(stats.paired_groups),
    "unresolved_groups": Json(stats.unresolved_groups),
    "missing_groups": Json(stats.missing_groups),
    "ambiguous_groups": Json(stats.ambiguous_groups),
    "pairing_status": Json::string(
      if stats.total_events == 0 {
        "no_events"
      } else if report.fully_paired() {
        "fully_paired"
      } else {
        "has_unresolved_groups"
      },
    ),
    "log_completeness": Json::string("unknown"),
  })
}

///|
fn unresolved_json(group : @correlate.UnresolvedGroup) -> Json {
  Json::object({
    "key": key_json(group.key),
    "send_event_ids": string_array(
      group.send_events.iter().map(e => e.event_id()).collect(),
    ),
    "receive_event_ids": string_array(
      group.receive_events.iter().map(e => e.event_id()).collect(),
    ),
    "issues": Json::array(
      group.issues
      .iter()
      .map(issue => {
        Json::string(
          match issue {
            @correlate.MissingSend => "missing_send"
            @correlate.MissingReceive => "missing_receive"
            @correlate.Ambiguous => "ambiguous"
          },
        )
      })
      .collect(),
    ),
  })
}
