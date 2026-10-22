///|
priv struct CliConfig {
  input_path : String
  output_path : String?
  format : String
  relation_tolerance_us : Int64
  reference_clock : String?
  input_limits : @input.InputLimits
  solve_limits : @solver.SolveLimits
  force : Bool
}

///|
priv enum CliConfigResult {
  Config(CliConfig)
  Invalid(String)
}

///|
fn cli_command() -> @argparse.Command {
  let input_defaults = @input.InputLimits::default()
  let solve_defaults = @solver.SolveLimits::default()
  @argparse.Command(
    "chronolens",
    about="Analyze distributed-log JSONL and emit a diagnostic report.",
    version="0.1.0",
    arg_required_else_help=true,
    positionals=[
      @argparse.PositionArg(
        "input",
        about="Path to a ChronoLens JSONL event file.",
      ),
    ],
    options=[
      @argparse.OptionArg(
        "format",
        long="format",
        about="Report format: json or markdown.",
        default_values=["json"],
      ),
      @argparse.OptionArg(
        "output",
        short='o',
        long="output",
        about="Write the report to a file instead of standard output.",
      ),
      @argparse.OptionArg(
        "reference_clock",
        long="reference-clock",
        about="Reference clock for component offset coordinates.",
      ),
      @argparse.OptionArg(
        "relation_tolerance_us",
        long="relation-tolerance-us",
        about="Non-negative message relation tolerance in microseconds.",
        default_values=["0"],
      ),
      @argparse.OptionArg(
        "max_input_bytes",
        long="max-input-bytes",
        about="Maximum accepted input size in UTF-8 bytes (hard cap: 67108864).",
        default_values=[input_defaults.max_input_bytes.to_string()],
      ),
      @argparse.OptionArg(
        "max_line_bytes",
        long="max-line-bytes",
        about="Maximum JSONL record size in UTF-8 bytes.",
        default_values=[input_defaults.max_line_bytes.to_string()],
      ),
      @argparse.OptionArg(
        "max_records",
        long="max-records",
        about="Maximum JSONL records to process.",
        default_values=[input_defaults.max_records.to_string()],
      ),
      @argparse.OptionArg(
        "max_clock_domains",
        long="max-clock-domains",
        about="Maximum number of distinct clock domains.",
        default_values=[input_defaults.max_clock_domains.to_string()],
      ),
      @argparse.OptionArg(
        "max_field_bytes",
        long="max-field-bytes",
        about="Maximum UTF-8 byte length of an input field.",
        default_values=[input_defaults.max_field_bytes.to_string()],
      ),
      @argparse.OptionArg(
        "max_issues",
        long="max-issues",
        about="Maximum input diagnostics to retain.",
        default_values=[input_defaults.max_issues.to_string()],
      ),
      @argparse.OptionArg(
        "max_json_depth",
        long="max-json-depth",
        about="Maximum JSON nesting depth (hard cap: 64).",
        default_values=[input_defaults.max_json_depth.to_string()],
      ),
      @argparse.OptionArg(
        "max_clocks",
        long="max-clocks",
        about="Maximum clocks to analyze (hard cap: 4096).",
        default_values=[solve_defaults.max_clocks.to_string()],
      ),
      @argparse.OptionArg(
        "max_constraints",
        long="max-constraints",
        about="Maximum difference constraints to build and analyze.",
        default_values=[solve_defaults.max_constraints.to_string()],
      ),
      @argparse.OptionArg(
        "max_edge_visits",
        long="max-edge-visits",
        about="Maximum solver edge visits (hard cap: 1000000000).",
        default_values=[solve_defaults.max_edge_visits.to_string()],
      ),
    ],
    flags=[
      @argparse.FlagArg(
        "force",
        long="force",
        about="Allow replacing an existing report file.",
      ),
    ],
  )
}

///|
fn option_value(matches : @argparse.Matches, name : String) -> String? {
  match matches.values.get(name) {
    Some(values) => values.get(0)
    None => None
  }
}

///|
fn option_value_or(
  matches : @argparse.Matches,
  name : String,
  fallback : String,
) -> String {
  match option_value(matches, name) {
    Some(value) => value
    None => fallback
  }
}

///|
fn parse_cli_config(matches : @argparse.Matches) -> CliConfigResult {
  let input_path = match option_value(matches, "input") {
    Some(value) => value
    None => return Invalid("missing input JSONL path")
  }
  let format = option_value_or(matches, "format", "json")
  if format != "json" && format != "markdown" {
    return Invalid("--format must be either json or markdown")
  }
  let relation_tolerance_us = @string.parse_int64(
    option_value_or(matches, "relation_tolerance_us", "0"),
    base=10,
  ) catch {
    _ => return Invalid("--relation-tolerance-us must be a decimal Int64")
  }
  if relation_tolerance_us < 0L {
    return Invalid("--relation-tolerance-us must be non-negative")
  }

  let input_defaults = @input.InputLimits::default()
  let max_input_bytes = @string.parse_int(
    option_value_or(
      matches,
      "max_input_bytes",
      input_defaults.max_input_bytes.to_string(),
    ),
    base=10,
  ) catch {
    _ => return Invalid("--max-input-bytes must be a positive decimal integer")
  }
  let max_line_bytes = @string.parse_int(
    option_value_or(
      matches,
      "max_line_bytes",
      input_defaults.max_line_bytes.to_string(),
    ),
    base=10,
  ) catch {
    _ => return Invalid("--max-line-bytes must be a positive decimal integer")
  }
  let max_records = @string.parse_int(
    option_value_or(
      matches,
      "max_records",
      input_defaults.max_records.to_string(),
    ),
    base=10,
  ) catch {
    _ => return Invalid("--max-records must be a positive decimal integer")
  }
  let max_clock_domains = @string.parse_int(
    option_value_or(
      matches,
      "max_clock_domains",
      input_defaults.max_clock_domains.to_string(),
    ),
    base=10,
  ) catch {
    _ =>
      return Invalid("--max-clock-domains must be a positive decimal integer")
  }
  let max_field_bytes = @string.parse_int(
    option_value_or(
      matches,
      "max_field_bytes",
      input_defaults.max_field_bytes.to_string(),
    ),
    base=10,
  ) catch {
    _ => return Invalid("--max-field-bytes must be a positive decimal integer")
  }
  let max_issues = @string.parse_int(
    option_value_or(
      matches,
      "max_issues",
      input_defaults.max_issues.to_string(),
    ),
    base=10,
  ) catch {
    _ => return Invalid("--max-issues must be a positive decimal integer")
  }
  let max_json_depth = @string.parse_int(
    option_value_or(
      matches,
      "max_json_depth",
      input_defaults.max_json_depth.to_string(),
    ),
    base=10,
  ) catch {
    _ => return Invalid("--max-json-depth must be a positive decimal integer")
  }
  let input_limits = @input.InputLimits::new(
    max_input_bytes~,
    max_line_bytes~,
    max_records~,
    max_clock_domains~,
    max_field_bytes~,
    max_issues~,
    max_json_depth~,
  ) catch {
    error => return Invalid("invalid input limits: " + @debug.to_string(error))
  }

  let solve_defaults = @solver.SolveLimits::default()
  let max_clocks = @string.parse_int(
    option_value_or(
      matches,
      "max_clocks",
      solve_defaults.max_clocks.to_string(),
    ),
    base=10,
  ) catch {
    _ => return Invalid("--max-clocks must be a positive decimal integer")
  }
  let max_constraints = @string.parse_int(
    option_value_or(
      matches,
      "max_constraints",
      solve_defaults.max_constraints.to_string(),
    ),
    base=10,
  ) catch {
    _ => return Invalid("--max-constraints must be a positive decimal integer")
  }
  let max_edge_visits = @string.parse_int64(
    option_value_or(
      matches,
      "max_edge_visits",
      solve_defaults.max_edge_visits.to_string(),
    ),
    base=10,
  ) catch {
    _ => return Invalid("--max-edge-visits must be a positive decimal Int64")
  }
  let solve_limits = @solver.SolveLimits::new(
    max_clocks~,
    max_constraints~,
    max_edge_visits~,
  ) catch {
    error => return Invalid("invalid solver limits: " + @debug.to_string(error))
  }

  let output_path = option_value(matches, "output")
  let force = match matches.flags.get("force") {
    Some(value) => value
    None => false
  }
  if force && output_path is None {
    return Invalid("--force requires --output")
  }
  let reference_clock = option_value(matches, "reference_clock")
  Config({
    input_path,
    output_path,
    format,
    relation_tolerance_us,
    reference_clock,
    input_limits,
    solve_limits,
    force,
  })
}

///|
fn is_utf8_continuation(byte : Int32) -> Bool {
  byte >= 0x80 && byte <= 0xBF
}

///|
/// Validate before calling x/unicode's decoder, which assumes valid UTF-8.
fn is_valid_utf8(bytes : Bytes) -> Bool {
  let length = bytes.length()
  let mut index = 0
  while index < length {
    let first = bytes[index].to_int()
    if first <= 0x7F {
      index += 1
    } else if first >= 0xC2 && first <= 0xDF {
      if index + 1 >= length || !is_utf8_continuation(bytes[index + 1].to_int()) {
        return false
      }
      index += 2
    } else if first == 0xE0 {
      if index + 2 >= length {
        return false
      }
      let second = bytes[index + 1].to_int()
      if second < 0xA0 ||
        second > 0xBF ||
        !is_utf8_continuation(bytes[index + 2].to_int()) {
        return false
      }
      index += 3
    } else if (first >= 0xE1 && first <= 0xEC) ||
      (first >= 0xEE && first <= 0xEF) {
      if index + 2 >= length ||
        !is_utf8_continuation(bytes[index + 1].to_int()) ||
        !is_utf8_continuation(bytes[index + 2].to_int()) {
        return false
      }
      index += 3
    } else if first == 0xED {
      if index + 2 >= length {
        return false
      }
      let second = bytes[index + 1].to_int()
      if second < 0x80 ||
        second > 0x9F ||
        !is_utf8_continuation(bytes[index + 2].to_int()) {
        return false
      }
      index += 3
    } else if first == 0xF0 {
      if index + 3 >= length {
        return false
      }
      let second = bytes[index + 1].to_int()
      if second < 0x90 ||
        second > 0xBF ||
        !is_utf8_continuation(bytes[index + 2].to_int()) ||
        !is_utf8_continuation(bytes[index + 3].to_int()) {
        return false
      }
      index += 4
    } else if first >= 0xF1 && first <= 0xF3 {
      if index + 3 >= length ||
        !is_utf8_continuation(bytes[index + 1].to_int()) ||
        !is_utf8_continuation(bytes[index + 2].to_int()) ||
        !is_utf8_continuation(bytes[index + 3].to_int()) {
        return false
      }
      index += 4
    } else if first == 0xF4 {
      if index + 3 >= length {
        return false
      }
      let second = bytes[index + 1].to_int()
      if second < 0x80 ||
        second > 0x8F ||
        !is_utf8_continuation(bytes[index + 2].to_int()) ||
        !is_utf8_continuation(bytes[index + 3].to_int()) {
        return false
      }
      index += 4
    } else {
      return false
    }
  }
  true
}

///|
/// Returns an output error code, or None when the report was emitted.
fn emit_report(
  report : @report.DiagnosticReport,
  input_path : String,
  config : CliConfig,
) -> Int32? {
  let content = if config.format == "markdown" {
    report.to_markdown()
  } else {
    report.stringify(pretty=true)
  }
  match config.output_path {
    None => {
      println(content)
      None
    }
    Some(path) => {
      if path == input_path {
        eprintln("ChronoLens: --output must not name the input file.")
        return Some(2)
      }
      if @fs.path_exists(path) && !config.force {
        eprintln(
          "ChronoLens: output file already exists; pass --force to replace it.",
        )
        return Some(2)
      }
      @fs.write_string_to_file(path, content + "\n") catch {
        error => {
          eprintln(
            "ChronoLens: failed to write report: " + @debug.to_string(error),
          )
          return Some(3)
        }
      }
      None
    }
  }
}

///|
fn finish_report(
  report : @report.DiagnosticReport,
  input_path : String,
  config : CliConfig,
  report_code : Int32,
) -> Int32 {
  match emit_report(report, input_path, config) {
    Some(error_code) => error_code
    None => report_code
  }
}

///|
fn analyzed_exit_code(report : @report.DiagnosticReport) -> Int32 {
  match report.to_json() {
    Json::Object(fields) =>
      match fields.get("has_conflicts") {
        Some(Json::True) => 1
        Some(Json::False) => 0
        _ => 5
      }
    _ => 5
  }
}

///|
fn analyze_file(config : CliConfig) -> Int32 {
  let max_input_bytes = config.input_limits.max_input_bytes.to_int64()
  let file_size = input_file_size(config.input_path)
  if file_size >= 0L && file_size > max_input_bytes {
    eprintln(
      "ChronoLens: input file has {file_size} bytes, exceeding --max-input-bytes={max_input_bytes}.",
    )
    return 4
  }
  let bytes = @fs.read_file_to_bytes(config.input_path) catch {
    error => {
      eprintln(
        "ChronoLens: failed to read input file: " + @debug.to_string(error),
      )
      return 3
    }
  }
  if bytes.length().to_int64() > max_input_bytes {
    eprintln(
      "ChronoLens: input file has {bytes.length()} bytes, exceeding --max-input-bytes={max_input_bytes}.",
    )
    return 4
  }
  if !is_valid_utf8(bytes) {
    eprintln("ChronoLens: input file is not valid UTF-8.")
    return 4
  }
  let text = @unicode.to_utf8_string(bytes)
  let parsed = @input.parse_jsonl(
    text,
    source_path=config.input_path,
    limits=config.input_limits,
  ) catch {
    error => {
      eprintln(
        "ChronoLens: invalid input configuration: " + @debug.to_string(error),
      )
      return 2
    }
  }
  if !parsed.is_valid() {
    return finish_report(
      @report.from_input(parsed),
      config.input_path,
      config,
      4,
    )
  }

  let correlation = @correlate.correlate_input(parsed) catch {
    error =>
      return finish_report(
        @report.from_failure(@report.Correlation(error), input=parsed),
        config.input_path,
        config,
        5,
      )
  }
  let constraints = @constraints.build(
    correlation,
    relation_tolerance_us=config.relation_tolerance_us,
    max_constraints=config.solve_limits.max_constraints,
  ) catch {
    error =>
      return finish_report(
        @report.from_failure(@report.ConstraintBuild(error), input=parsed),
        config.input_path,
        config,
        5,
      )
  }
  let analysis = match config.reference_clock {
    Some(reference_clock) =>
      @solver.analyze(constraints, reference_clock~, limits=config.solve_limits) catch {
        error =>
          return finish_report(
            @report.from_failure(@report.Solver(error), input=parsed),
            config.input_path,
            config,
            5,
          )
      }
    None =>
      @solver.analyze(constraints, limits=config.solve_limits) catch {
        error =>
          return finish_report(
            @report.from_failure(@report.Solver(error), input=parsed),
            config.input_path,
            config,
            5,
          )
      }
  }
  let report = @report.from_analysis(analysis, input=parsed) catch {
    error => {
      eprintln(
        "ChronoLens: failed to construct diagnostic report: " +
        @debug.to_string(error),
      )
      return 5
    }
  }
  finish_report(report, config.input_path, config, analyzed_exit_code(report))
}

///|
fn run_cli() -> Int32 {
  let matches = cli_command().parse() catch {
    error => {
      eprintln(@debug.to_string(error))
      return 2
    }
  }
  let config = match parse_cli_config(matches) {
    Config(config) => config
    Invalid(message) => {
      eprintln("ChronoLens: " + message)
      return 2
    }
  }
  analyze_file(config)
}

///|
fn main {
  @sys.exit(run_cli())
}
