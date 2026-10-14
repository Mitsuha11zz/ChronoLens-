///|
priv suberror TextError {
  MalformedUnicode
  TooManyBytes
}

///|
/// Validate Unicode and bound UTF-8 size without allocating an encoded copy.
fn check_text(text : StringView, cap : Int) -> Unit raise TextError {
  let mut i = 0
  let mut bytes = 0
  while i < text.length() {
    let c = text[i]
    let step = if c < 0x80 {
      1
    } else if c < 0x800 {
      2
    } else if c >= 0xD800 && c <= 0xDBFF {
      if i + 1 >= text.length() {
        raise MalformedUnicode
      }
      let next = text[i + 1]
      if next < 0xDC00 || next > 0xDFFF {
        raise MalformedUnicode
      }
      i += 1
      4
    } else if c >= 0xDC00 && c <= 0xDFFF {
      raise MalformedUnicode
    } else {
      3
    }
    if bytes > cap - step {
      raise TooManyBytes
    }
    bytes += step
    i += 1
  }
}

///|
fn decimal_digits(text : StringView, signed~ : Bool) -> Bool {
  if text.is_empty() {
    return false
  }
  let start = if signed && text[0] == '-' { 1 } else { 0 }
  if start == text.length() {
    return false
  }
  for i in start..<text.length() {
    if text[i] < '0' || text[i] > '9' {
      return false
    }
  }
  true
}

///|
fn timestamp(text : String, cap : Int) -> Int64 raise DecodeIssue {
  check_field(text, "ts_us", cap)
  if !decimal_digits(text, signed=true) {
    raise DecodeIssue(InvalidValue("ts_us"))
  }
  @string.parse_int64(text, base=10) catch {
    _ => raise DecodeIssue(InvalidValue("ts_us"))
  }
}

///|
fn check_field(
  text : String,
  field : String,
  cap : Int,
) -> Unit raise DecodeIssue {
  check_text(text, cap) catch {
    MalformedUnicode => raise DecodeIssue(InvalidValue(field))
    TooManyBytes => raise DecodeIssue(LimitExceeded("max_field_bytes"))
  }
}

///|
// Bound nesting before invoking the JSON parser. Strings and escapes do not
// affect structural depth; JSON grammar is still validated by the core parser.
fn check_depth(text : StringView, cap : Int) -> Unit raise DecodeIssue {
  let mut depth = 0
  let mut in_string = false
  let mut escaped = false
  for i in 0..<text.length() {
    let c = text[i]
    if in_string {
      if escaped {
        escaped = false
      } else if c == '\\' {
        escaped = true
      } else if c == '"' {
        in_string = false
      }
    } else if c == '"' {
      in_string = true
    } else if c == '{' || c == '[' {
      depth += 1
      if depth > cap {
        raise DecodeIssue(LimitExceeded("max_json_depth"))
      }
    } else if c == '}' || c == ']' {
      depth -= 1
      if depth < 0 {
        raise DecodeIssue(InvalidJson)
      }
    }
  }
}
