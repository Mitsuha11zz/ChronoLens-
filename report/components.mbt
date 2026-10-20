///|
fn stats_json(stats : @solver.SolveStats) -> Json {
  Json::object({
    "clock_count": Json(stats.clock_count),
    "constraint_count": Json(stats.constraint_count),
    "passes": Json(stats.passes),
    "edge_visits": Json::string(stats.edge_visits.to_string()),
  })
}

///|
fn bound_json(bound : @solver.OffsetBound) -> Json {
  match bound {
    @solver.Finite(value) =>
      Json::object({
        "kind": Json::string("finite"),
        "value_us": Json::string(value.to_string()),
      })
    @solver.Unbounded => Json::object({ "kind": Json::string("unbounded") })
  }
}

///|
fn component_json(component : @solver.ComponentAnalysis) -> Json {
  let fields : Map[String, Json] = {
    "component_id": Json(component.component_id),
    "clock_ids": string_array(component.clocks),
    "reference_clock": Json::string(component.reference_clock),
    "constraint_indices": index_array(component.constraint_indices),
    "stats": stats_json(component.stats),
    "offsets": Json::null(),
    "intervals": Json::null(),
    "cycle": Json::null(),
    "error": Json::null(),
  }
  match component.outcome {
    @solver.ComponentFeasible(offsets~, intervals~) => {
      fields["status"] = Json::string("feasible")
      fields["offsets"] = Json::array(
        offsets
        .iter()
        .map(offset => {
          Json::object({
            "clock_id": Json::string(offset.clock_id),
            "offset_us": Json::string(offset.offset_us.to_string()),
          })
        })
        .collect(),
      )
      fields["intervals"] = Json::array(
        intervals
        .iter()
        .map(interval => {
          Json::object({
            "clock_id": Json::string(interval.clock_id),
            "lower": bound_json(interval.lower),
            "upper": bound_json(interval.upper),
          })
        })
        .collect(),
      )
    }
    @solver.ComponentInfeasible(cycle~) => {
      fields["status"] = Json::string("infeasible")
      fields["cycle"] = Json::object({
        "constraint_indices": index_array(
          cycle.edges.iter().map(edge => edge.constraint_index).collect(),
        ),
        "total_weight_us": Json::string(cycle.total_weight_us.to_string()),
        "minimum_conflict_guaranteed": Json::boolean(false),
      })
    }
    @solver.ComponentFailed(error~) => {
      fields["status"] = Json::string("failed")
      fields["error"] = solver_error_json(error)
    }
  }
  Json::object(fields)
}

///|
fn analysis_summary(
  analysis : @solver.ConstraintAnalysis,
) -> (String, Json, Bool?) {
  let mut feasible = 0
  let mut infeasible = 0
  let mut failed = 0
  let mut unbounded_clocks = 0
  for component in analysis.components {
    match component.outcome {
      @solver.ComponentFeasible(intervals~, ..) => {
        feasible += 1
        for interval in intervals {
          if interval.lower == @solver.Unbounded ||
            interval.upper == @solver.Unbounded {
            unbounded_clocks += 1
          }
        }
      }
      @solver.ComponentInfeasible(_) => infeasible += 1
      @solver.ComponentFailed(_) => failed += 1
    }
  }
  let status = if failed > 0 {
    "analysis_incomplete"
  } else if infeasible > 0 {
    "infeasible"
  } else if analysis.constraints.is_empty() {
    "no_constraints"
  } else {
    "feasible"
  }
  (
    status,
    Json::object({
      "component_count": Json(analysis.components.length()),
      "feasible_components": Json(feasible),
      "infeasible_components": Json(infeasible),
      "failed_components": Json(failed),
      "unbounded_clock_count": Json(unbounded_clocks),
      "stats": stats_json(analysis.stats),
    }),
    if infeasible > 0 {
      Some(true)
    } else if failed > 0 {
      None
    } else {
      Some(false)
    },
  )
}
