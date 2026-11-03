///|
priv enum PriorFileDecode {
  PriorDocumentDecoded(Array[@constraints.OffsetPrior])
  PriorDocumentInvalid(String)
}

///|
priv enum PriorFileLoad {
  PriorFileLoaded(Array[@constraints.OffsetPrior])
  PriorFileInvalid(String)
  PriorFileReadFailure(String)
  PriorFileTooLarge
}

///|
/// Reject nested JSON bombs and duplicate object keys before materializing the
/// JSON value. A prior document only needs an array of flat objects.
fn prior_json_preflight_issue(text : String) -> String? {
  let stack : Array[Map[String, Unit]?] = []
  let mut i = 0
  while i < text.length() {
    let c = text[i]
    if c == '{' {
      stack.push(Some(Map([])))
      if stack.length() > 3 {
        return Some("JSON nesting exceeds the supported prior-file shape")
      }
      i += 1
    } else if c == '[' {
      stack.push(None)
      if stack.length() > 3 {
        return Some("JSON nesting exceeds the supported prior-file shape")
      }
      i += 1
    } else if c == '}' || c == ']' {
      ignore(stack.pop())
      i += 1
    } else if c == '"' {
      let start = i
      i += 1
      let mut escaped = false
      while i < text.length() {
        let current = text[i]
        i += 1
        if escaped {
          escaped = false
        } else if current == '\\' {
          escaped = true
        } else if current == '"' {
          break
        }
      }
      let mut next = i
      while next < text.length() &&
            (
              text[next] == ' ' ||
              text[next] == '\t' ||
              text[next] == '\r' ||
              text[next] == '\n'
            ) {
        next += 1
      }
      if next < text.length() && text[next] == ':' {
        if stack.last() is Some(Some(keys)) {
          let parsed_key = @json.parse(text[start:i]) catch {
            _ => return Some("invalid JSON property name")
          }
          guard parsed_key is String(name) else {
            return Some("invalid JSON property name")
          }
          if keys.contains(name) {
            return Some("duplicate JSON property: " + name)
          }
          keys[name] = ()
        }
      }
    } else {
      i += 1
    }
  }
  None
}

///|
fn prior_bound(fields : Map[String, Json], name : String) -> (Int64?, Bool) {
  match fields.get(name) {
    None | Some(Json::Null) => (None, true)
    Some(Json::String(text)) => {
      let value = @string.parse_int64(text, base=10) catch {
        _ => return (None, false)
      }
      (Some(value), true)
    }
    _ => (None, false)
  }
}

///|
fn prior_required_string(fields : Map[String, Json], name : String) -> String? {
  match fields.get(name) {
    Some(Json::String(value)) => Some(value)
    _ => None
  }
}

///|
fn create_offset_prior(
  clock_id : String,
  reference_clock : String,
  label : String,
  lower_us : Int64?,
  upper_us : Int64?,
) -> @constraints.OffsetPrior raise @constraints.ConstraintBuildError {
  match (lower_us, upper_us) {
    (Some(lower), Some(upper)) =>
      @constraints.OffsetPrior::new(
        clock_id~,
        reference_clock~,
        label~,
        lower_us=lower,
        upper_us=upper,
      )
    (Some(lower), None) =>
      @constraints.OffsetPrior::new(
        clock_id~,
        reference_clock~,
        label~,
        lower_us=lower,
      )
    (None, Some(upper)) =>
      @constraints.OffsetPrior::new(
        clock_id~,
        reference_clock~,
        label~,
        upper_us=upper,
      )
    (None, None) =>
      @constraints.OffsetPrior::new(clock_id~, reference_clock~, label~)
  }
}

///|
fn decode_prior_file(text : String) -> PriorFileDecode {
  match prior_json_preflight_issue(text) {
    Some(problem) => return PriorDocumentInvalid(problem)
    None => ()
  }
  let parsed = @json.parse(text) catch {
    error =>
      return PriorDocumentInvalid("invalid JSON: " + @debug.to_string(error))
  }
  guard parsed is Json::Array(entries) else {
    return PriorDocumentInvalid("top-level value must be an array")
  }
  if entries.length() > 4096 {
    return PriorDocumentInvalid("prior file contains more than 4096 entries")
  }

  let priors : Array[@constraints.OffsetPrior] = []
  let labels : Map[String, Unit] = Map([])
  for entry in entries {
    guard entry is Json::Object(fields) else {
      return PriorDocumentInvalid("prior entry must be an object")
    }
    for name, _ in fields {
      match name {
        "clock_id" | "reference_clock" | "label" | "lower_us" | "upper_us" => ()
        _ => return PriorDocumentInvalid("unsupported prior field: " + name)
      }
    }
    let clock_id = match prior_required_string(fields, "clock_id") {
      Some(value) => value
      None =>
        return PriorDocumentInvalid("required string field missing: clock_id")
    }
    let reference_clock = match
      prior_required_string(fields, "reference_clock") {
      Some(value) => value
      None =>
        return PriorDocumentInvalid(
          "required string field missing: reference_clock",
        )
    }
    let label = match prior_required_string(fields, "label") {
      Some(value) => value
      None =>
        return PriorDocumentInvalid("required string field missing: label")
    }
    if labels.contains(label) {
      return PriorDocumentInvalid("duplicate prior label: " + label)
    }
    let (lower_us, lower_valid) = prior_bound(fields, "lower_us")
    let (upper_us, upper_valid) = prior_bound(fields, "upper_us")
    if !lower_valid {
      return PriorDocumentInvalid(
        "lower_us must be a decimal Int64 string or null",
      )
    }
    if !upper_valid {
      return PriorDocumentInvalid(
        "upper_us must be a decimal Int64 string or null",
      )
    }
    let prior = create_offset_prior(
      clock_id, reference_clock, label, lower_us, upper_us,
    ) catch {
      error =>
        return PriorDocumentInvalid(
          "invalid offset prior: " + @debug.to_string(error),
        )
    }
    labels[label] = ()
    priors.push(prior)
  }
  PriorDocumentDecoded(priors)
}

///|
fn load_prior_file(path : String) -> PriorFileLoad {
  let size = input_file_size(path)
  if size > 1048576L {
    return PriorFileTooLarge
  }
  let bytes = @fs.read_file_to_bytes(path) catch {
    error => return PriorFileReadFailure(@debug.to_string(error))
  }
  if bytes.length().to_int64() > 1048576L {
    return PriorFileTooLarge
  }
  if !is_valid_utf8(bytes) {
    return PriorFileInvalid("prior file is not valid UTF-8")
  }
  match decode_prior_file(@unicode.to_utf8_string(bytes)) {
    PriorDocumentDecoded(priors) => PriorFileLoaded(priors)
    PriorDocumentInvalid(message) => PriorFileInvalid(message)
  }
}
