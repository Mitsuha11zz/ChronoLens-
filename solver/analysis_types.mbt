///|
/// Unbounded is mathematical unboundedness, not a computation failure.
pub(all) enum OffsetBound {
  Finite(Int64)
  Unbounded
} derive(Debug, Eq)

///|
/// Marginal bounds relative to the component reference. Endpoints for different
/// clocks need not be simultaneously attainable.
pub struct OffsetInterval {
  clock_id : String
  lower : OffsetBound
  upper : OffsetBound
} derive(Debug, Eq)

///|
pub(all) enum ComponentOutcome {
  ComponentFeasible(
    offsets~ : ReadOnlyArray[ClockOffset],
    intervals~ : ReadOnlyArray[OffsetInterval]
  )
  ComponentInfeasible(cycle~ : NegativeCycle)
  ComponentFailed(error~ : SolveError)
} derive(Debug, Eq)

///|
/// Component IDs are zero-based in order of the smallest clock name.
/// Constraint indices and cycle indices refer to the original global array.
pub struct ComponentAnalysis {
  component_id : Int
  clocks : ReadOnlyArray[String]
  reference_clock : String
  constraint_indices : ReadOnlyArray[Int]
  outcome : ComponentOutcome
  stats : SolveStats
} derive(Debug, Eq)

///|
/// A completed component traversal may contain ComponentFailed outcomes.
/// Always inspect each outcome; this report is not a global feasibility claim.
pub struct ConstraintAnalysis {
  clocks : ReadOnlyArray[String]
  constraints : ReadOnlyArray[@model.DifferenceConstraint]
  components : ReadOnlyArray[ComponentAnalysis]
  stats : SolveStats
} derive(Debug, Eq)

///|
pub struct AnalysisReport {
  input : @constraints.ConstraintSet
  analysis : ConstraintAnalysis
} derive(Debug, Eq)
