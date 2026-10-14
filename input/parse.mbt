///|
/// Parse LF-delimited JSON objects, allowing CRLF and blank lines.
/// Errors retain physical line numbers. Error reports are not analysis-ready.
pub fn parse_jsonl(
  text : String,
  source_path? : String = "<memory>",
  limits? : InputLimits = InputLimits::default(),
) -> InputReport raise InputConfigError {
  check_text(source_path, limits.max_field_bytes) catch {
    _ => raise InvalidSourcePath
  }
  if source_path.trim().is_empty() {
    raise InvalidSourcePath
  }
  let accepted_events : Array[@model.Event] = []
  let issues : Array[InputIssue] = []
  let mut status = Complete
  let mut records_seen = 0
  check_text(text, limits.max_input_bytes) catch {
    MalformedUnicode => {
      issues.push({ line: None, kind: InvalidValue("unicode"), })
      return make_report(accepted_events, issues, status, records_seen)
    }
    TooManyBytes => {
      issues.push({ line: None, kind: LimitExceeded("max_input_bytes"), })
      return make_report(
        accepted_events,
        issues,
        Limited("max_input_bytes"),
        records_seen,
      )
    }
  }
  let ids : Map[String, Int] = Map([])
  let clocks : Map[String, Unit] = Map([])
  let mut line = 0
  for raw in text.split("\n") {
    line += 1
    check_text(raw, limits.max_line_bytes) catch {
      _ => {
        issues.push({ line: Some(line), kind: LimitExceeded("max_line_bytes"), })
        status = Limited("max_line_bytes")
        break
      }
    }
    if raw.trim().is_empty() {
      continue
    }
    if records_seen >= limits.max_records {
      issues.push({ line: Some(line), kind: LimitExceeded("max_records"), })
      status = Limited("max_records")
      break
    }
    records_seen += 1
    try decode_record(raw, line, source_path, limits) catch {
      DecodeIssue(kind) => issues.push({ line: Some(line), kind, })
    } noraise {
      event =>
        match ids.get(event.event_id()) {
          Some(first_line) =>
            issues.push({
              line: Some(line),
              kind: DuplicateEventId(first_line~),
            })
          None => {
            if !clocks.contains(event.clock_id()) &&
              clocks.length() >= limits.max_clock_domains {
              issues.push({
                line: Some(line),
                kind: LimitExceeded("max_clock_domains"),
              })
              status = Limited("max_clock_domains")
              break
            }
            ids[event.event_id()] = line
            clocks[event.clock_id()] = ()
            accepted_events.push(event)
          }
        }
    }
    if issues.length() >= limits.max_issues {
      status = Limited("max_issues")
      break
    }
  }
  if records_seen == 0 && status == Complete {
    issues.push({ line: None, kind: EmptyInput, })
  }
  make_report(accepted_events, issues, status, records_seen)
}
