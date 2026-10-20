///|
fn phase_text(phase : @solver.SolvePhase) -> String {
  match phase {
    @solver.Relaxation => "relaxation"
    @solver.FeasibleVerification => "feasible_verification"
    @solver.CycleWeightSum => "cycle_weight_sum"
    @solver.UpperBoundPaths => "upper_bound_paths"
    @solver.LowerBoundPaths => "lower_bound_paths"
  }
}

///|
fn solver_error_json(error : @solver.SolveError) -> Json {
  let details : Map[String, Json] = Map([])
  let code = match error {
    @solver.InvalidLimit(name) => {
      details["limit"] = Json::string(name)
      "invalid_limit"
    }
    @solver.ClockLimitExceeded(limit) => {
      details["limit"] = Json(limit)
      "clock_limit_exceeded"
    }
    @solver.ConstraintLimitExceeded(limit) => {
      details["limit"] = Json(limit)
      "constraint_limit_exceeded"
    }
    @solver.EmptyClockId => "empty_clock_id"
    @solver.UnknownReferenceClock(clock) => {
      details["clock_id"] = Json::string(clock)
      "unknown_reference_clock"
    }
    @solver.OffsetOverflow(clock_id~, reference_clock~) => {
      details["clock_id"] = Json::string(clock_id)
      details["reference_clock"] = Json::string(reference_clock)
      "offset_overflow"
    }
    @solver.BoundOverflow(clock_id~, lower_bound~) => {
      details["clock_id"] = Json::string(clock_id)
      details["bound"] = Json::string(
        if lower_bound {
          "lower"
        } else {
          "upper"
        },
      )
      "bound_overflow"
    }
    @solver.EdgeVisitLimitExceeded(limit) => {
      details["limit"] = Json::string(limit.to_string())
      "edge_visit_limit_exceeded"
    }
    @solver.ArithmeticOverflow(phase~, constraint_index~) => {
      details["phase"] = Json::string(phase_text(phase))
      details["constraint_index"] = Json(constraint_index)
      "arithmetic_overflow"
    }
    @solver.InvalidWitness => "invalid_witness"
  }
  Json::object({ "code": Json::string(code), "details": Json::object(details) })
}

///|
fn correlation_error_json(error : @correlate.CorrelationError) -> Json {
  let details : Map[String, Json] = Map([])
  let code = match error {
    @correlate.InvalidInput => "invalid_input"
    @correlate.InvalidEventLimit => "invalid_event_limit"
    @correlate.EventLimitExceeded(limit~, count~) => {
      details["limit"] = Json(limit)
      details["count"] = Json(count)
      "event_limit_exceeded"
    }
    @correlate.DuplicateEventId(id) => {
      details["event_id"] = Json::string(id)
      "duplicate_event_id"
    }
  }
  Json::object({ "code": Json::string(code), "details": Json::object(details) })
}

///|
fn build_error_json(error : @constraints.ConstraintBuildError) -> Json {
  let details : Map[String, Json] = Map([])
  let code = match error {
    @constraints.InvalidTolerance => "invalid_tolerance"
    @constraints.InvalidPriorField(field) => {
      details["field"] = Json::string(field)
      "invalid_prior_field"
    }
    @constraints.EmptyPriorBounds(label) => {
      details["label"] = Json::string(label)
      "empty_prior_bounds"
    }
    @constraints.InvertedPriorRange(label) => {
      details["label"] = Json::string(label)
      "inverted_prior_range"
    }
    @constraints.DuplicatePriorLabel(label) => {
      details["label"] = Json::string(label)
      "duplicate_prior_label"
    }
    @constraints.InvalidConstraintLimit => "invalid_constraint_limit"
    @constraints.ConstraintLimitExceeded(limit) => {
      details["limit"] = Json(limit)
      "constraint_limit_exceeded"
    }
    @constraints.ArithmeticOverflow(origin) => {
      details["origin"] = origin_json(origin)
      "arithmetic_overflow"
    }
  }
  Json::object({ "code": Json::string(code), "details": Json::object(details) })
}

///|
fn input_config_error_json(error : @input.InputConfigError) -> Json {
  let details : Map[String, Json] = Map([])
  let code = match error {
    @input.InvalidLimit(name) => {
      details["limit"] = Json::string(name)
      "invalid_limit"
    }
    @input.InvalidSourcePath => "invalid_source_path"
  }
  Json::object({ "code": Json::string(code), "details": Json::object(details) })
}

///|
fn pipeline_error_json(failure : PipelineFailure) -> Json {
  let (stage, error) = match failure {
    InputConfiguration(error) =>
      ("input_configuration", input_config_error_json(error))
    Correlation(error) => ("correlation", correlation_error_json(error))
    ConstraintBuild(error) => ("constraint_build", build_error_json(error))
    Solver(error) => ("solver", solver_error_json(error))
  }
  Json::object({ "stage": Json::string(stage), "error": error })
}
