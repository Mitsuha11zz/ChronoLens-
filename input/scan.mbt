///|
// Run only after the core parser has validated JSON grammar. Track keys for
// each object separately and decode escaped names before checking equality.
// Preserve numeric metadata text before Double rounding loses precision.
// The valid event schema permits only source as a second-level object.
fn scan_record_fields(
  text : StringView,
  cap : Int,
) -> (String?, String?) raise DecodeIssue {
  let stack : Array[Map[String, Unit]?] = []
  let mut attempt_literal : String? = None
  let mut source_line_literal : String? = None
  let mut i = 0
  while i < text.length() {
    let c = text[i]
    if c == '{' {
      stack.push(Some(Map([])))
      i += 1
    } else if c == '[' {
      stack.push(None)
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
          let key = @json.parse(text[start:i]) catch {
            _ => raise DecodeIssue(InvalidJson)
          }
          guard key is String(name) else { raise DecodeIssue(InvalidJson) }
          check_field(name, "property_name", cap)
          if keys.contains(name) {
            raise DecodeIssue(DuplicateField(name))
          }
          keys[name] = ()
          if (stack.length() == 1 && name == "attempt") ||
            (stack.length() == 2 && name == "line") {
            let mut value_start = next + 1
            while value_start < text.length() &&
                  (
                    text[value_start] == ' ' ||
                    text[value_start] == '\t' ||
                    text[value_start] == '\r' ||
                    text[value_start] == '\n'
                  ) {
              value_start += 1
            }
            let mut value_end = value_start
            while value_end < text.length() &&
                  text[value_end] != ',' &&
                  text[value_end] != '}' &&
                  text[value_end] != ']' &&
                  text[value_end] != ' ' &&
                  text[value_end] != '\t' &&
                  text[value_end] != '\r' &&
                  text[value_end] != '\n' {
              value_end += 1
            }
            let literal = text[value_start:value_end].to_owned()
            if stack.length() == 1 {
              attempt_literal = Some(literal)
            } else {
              source_line_literal = Some(literal)
            }
          }
        }
      }
    } else {
      i += 1
    }
  }
  (attempt_literal, source_line_literal)
}
