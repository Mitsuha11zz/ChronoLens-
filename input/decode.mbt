///|
priv suberror DecodeIssue {
  DecodeIssue(IssueKind)
}

///|
fn read_string(
  object : Map[String, Json],
  name : String,
  cap : Int,
) -> String raise DecodeIssue {
  let text = match object.get(name) {
    None => raise DecodeIssue(MissingField(name))
    Some(String(text)) => text
    _ => raise DecodeIssue(WrongType(name))
  }
  check_field(text, name, cap)
  text
}

///|
fn read_integer(
  object : Map[String, Json],
  name : String,
  literal : String?,
) -> Int raise DecodeIssue {
  match object.get(name) {
    None => raise DecodeIssue(MissingField(name))
    Some(Number(_, ..)) => ()
    _ => raise DecodeIssue(WrongType(name))
  }
  guard literal is Some(text) else { raise DecodeIssue(InvalidValue(name)) }
  match exact_nonnegative_integer(text) {
    Some(value) => value
    None => raise DecodeIssue(InvalidValue(name))
  }
}

///|
fn decode_record(
  text : StringView,
  line : Int,
  source_path : String,
  limits : InputLimits,
) -> @model.Event raise DecodeIssue {
  check_depth(text, limits.max_json_depth)
  let json = @json.parse(text) catch { _ => raise DecodeIssue(InvalidJson) }
  let (attempt_literal, source_line_literal) = scan_record_fields(
    text,
    limits.max_line_bytes,
  )
  guard json is Object(object) else { raise DecodeIssue(ExpectedObject) }
  for name, _ in object {
    match name {
      "event_id"
      | "clock_id"
      | "trace_id"
      | "message_id"
      | "attempt"
      | "kind"
      | "ts_us"
      | "source" => ()
      _ => raise DecodeIssue(UnknownField(name))
    }
  }
  let event_id = read_string(object, "event_id", limits.max_field_bytes)
  let clock_id = read_string(object, "clock_id", limits.max_field_bytes)
  let trace_id = read_string(object, "trace_id", limits.max_field_bytes)
  let message_id = read_string(object, "message_id", limits.max_field_bytes)
  let attempt = read_integer(object, "attempt", attempt_literal)
  let kind = match read_string(object, "kind", limits.max_field_bytes) {
    "send" => @model.Send
    "receive" => @model.Receive
    _ => raise DecodeIssue(InvalidValue("kind"))
  }
  let timestamp_us = timestamp(
    read_string(object, "ts_us", limits.max_field_bytes),
    limits.max_field_bytes,
  )
  let (path, source_line) = match object.get("source") {
    None => (source_path, line)
    Some(Object(source)) => {
      for name, _ in source {
        if name != "path" && name != "line" {
          raise DecodeIssue(UnknownField("source." + name))
        }
      }
      (
        read_string(source, "path", limits.max_field_bytes),
        read_integer(source, "line", source_line_literal),
      ) catch {
        DecodeIssue(MissingField(name)) =>
          raise DecodeIssue(MissingField("source." + name))
        DecodeIssue(WrongType(name)) =>
          raise DecodeIssue(WrongType("source." + name))
        DecodeIssue(InvalidValue(name)) =>
          raise DecodeIssue(InvalidValue("source." + name))
        err => raise err
      }
    }
    _ => raise DecodeIssue(WrongType("source"))
  }
  try {
    let key = @model.MessageKey::new(trace_id~, message_id~, attempt~)
    let source = @model.SourceLocation::new(path~, line=source_line)
    @model.Event::new(event_id~, clock_id~, key~, kind~, timestamp_us~, source~)
  } catch {
    @model.EmptyIdentifier(field) => raise DecodeIssue(InvalidValue(field))
    @model.InvalidAttempt(_) => raise DecodeIssue(InvalidValue("attempt"))
    @model.InvalidSourceLine(_) =>
      raise DecodeIssue(InvalidValue("source.line"))
  }
}
