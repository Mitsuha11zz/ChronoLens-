///|
fn indent_line(builder : StringBuilder, width : Int32, depth : Int32) -> Unit {
  builder.write_char('\n')
  for i = 0; i < width * depth; i = i + 1 {
    builder.write_char(' ')
  }
}

///|
/// Object order is explicit, independent of map iteration and backend.
/// Only primitive escaping/number formatting is delegated to core JSON.
fn write_canonical(
  value : Json,
  builder : StringBuilder,
  width : Int32,
  depth : Int32,
) -> Unit {
  match value {
    Object(fields) => {
      let keys = Array::from_iter(fields.keys())
      keys.sort_by((a, b) => a.lexical_compare(b))
      builder.write_char('{')
      for i, key in keys {
        if i > 0 {
          builder.write_char(',')
        }
        if width > 0 {
          indent_line(builder, width, depth + 1)
        }
        builder.write_string(Json::string(key).stringify())
        builder.write_char(':')
        if width > 0 {
          builder.write_char(' ')
        }
        write_canonical(fields[key], builder, width, depth + 1)
      }
      if width > 0 && !keys.is_empty() {
        indent_line(builder, width, depth)
      }
      builder.write_char('}')
    }
    Array(values) => {
      builder.write_char('[')
      for i, item in values {
        if i > 0 {
          builder.write_char(',')
        }
        if width > 0 {
          indent_line(builder, width, depth + 1)
        }
        write_canonical(item, builder, width, depth + 1)
      }
      if width > 0 && !values.is_empty() {
        indent_line(builder, width, depth)
      }
      builder.write_char(']')
    }
    _ => builder.write_string(value.stringify())
  }
}
