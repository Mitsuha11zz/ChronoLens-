///|
// Interpret a grammar-validated JSON decimal exactly, without Double rounding.
fn exact_nonnegative_integer(text : String) -> Int? {
  if text.is_empty() {
    return None
  }
  let negative = text[0] == '-'
  let mut index = if negative { 1 } else { 0 }
  let digits : Array[Int] = []
  let mut fractional_digits = 0
  let mut fraction = false
  let mut first_nonzero : Int? = None
  while index < text.length() {
    let c = text[index]
    if c == 'e' || c == 'E' {
      break
    }
    if c == '.' {
      fraction = true
    } else {
      if c < '0' || c > '9' {
        return None
      }
      let digit = c.to_int() - 48
      if digit != 0 && first_nonzero is None {
        first_nonzero = Some(digits.length())
      }
      digits.push(digit)
      if fraction {
        fractional_digits += 1
      }
    }
    index += 1
  }
  let mut exponent = 0
  let mut negative_exponent = false
  // Saturating beyond token length cannot change the answer for a nonzero
  // coefficient: it either overflows Int or retains a fractional component.
  let exponent_cap = text.length() + 10
  if index < text.length() {
    index += 1
    if index < text.length() && (text[index] == '+' || text[index] == '-') {
      negative_exponent = text[index] == '-'
      index += 1
    }
    while index < text.length() {
      let c = text[index]
      if c < '0' || c > '9' {
        return None
      }
      let digit = c.to_int() - 48
      exponent = if exponent > (exponent_cap - digit) / 10 {
        exponent_cap
      } else {
        exponent * 10 + digit
      }
      index += 1
    }
  }
  guard first_nonzero is Some(first) else { return Some(0) }
  if negative {
    return None
  }
  if negative_exponent {
    exponent = -exponent
  }
  let scale = exponent - fractional_digits
  let mut end = digits.length()
  let mut zeroes_to_add = 0
  if scale < 0 {
    let remove = -scale
    if remove > end - first {
      return None
    }
    for i in (end - remove)..<end {
      if digits[i] != 0 {
        return None
      }
    }
    end -= remove
  } else {
    zeroes_to_add = scale
  }
  if end - first + zeroes_to_add > 10 {
    return None
  }
  let mut value = 0
  for i in first..<end {
    let digit = digits[i]
    if value > (2147483647 - digit) / 10 {
      return None
    }
    value = value * 10 + digit
  }
  for _ in 0..<zeroes_to_add {
    if value > 2147483647 / 10 {
      return None
    }
    value *= 10
  }
  Some(value)
}
