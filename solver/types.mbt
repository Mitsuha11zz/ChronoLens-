///|
/// Offsets use the same relative coordinate system, with no UTC anchor.
/// The implicit zero-cost super-source makes every returned offset <= 0.
pub struct ClockOffset {
  clock_id : String
  offset_us : Int64
} derive(Debug, Eq)

///|
/// Index into ConstraintSolution.constraints, and (for solve) into
/// SolveReport.input.constraints. The original constraint is retained.
pub struct CycleEdge {
  constraint_index : Int
  constraint : @model.DifferenceConstraint
} derive(Debug, Eq)

///|
/// Edges are in forward traversal order. The last edge returns to the first.
/// This is one conflict witness, not necessarily a minimum conflict.
pub struct NegativeCycle {
  edges : ReadOnlyArray[CycleEdge]
  total_weight_us : Int64
} derive(Debug, Eq)

///|
pub(all) enum Feasibility {
  Feasible(offsets~ : ReadOnlyArray[ClockOffset])
  Infeasible(cycle~ : NegativeCycle)
} derive(Debug, Eq)

///|
pub struct SolveStats {
  clock_count : Int
  constraint_count : Int
  passes : Int
  edge_visits : Int64
} derive(Debug, Eq)

///|
/// Original edge order is preserved. Independent clocks are sorted by name.
/// A feasible result covers only these supplied constraints, not log coverage.
pub struct ConstraintSolution {
  clocks : ReadOnlyArray[String]
  constraints : ReadOnlyArray[@model.DifferenceConstraint]
  outcome : Feasibility
  stats : SolveStats
} derive(Debug, Eq)

///|
/// Includes missing/ambiguous correlation groups and full edge evidence.
pub struct SolveReport {
  input : @constraints.ConstraintSet
  solution : ConstraintSolution
} derive(Debug, Eq)

///|
pub(all) enum SolvePhase {
  Relaxation
  FeasibleVerification
  CycleWeightSum
} derive(Debug, Eq)

///|
/// Errors carry no feasibility verdict or partial solution.
pub(all) suberror SolveError {
  InvalidLimit(String)
  ClockLimitExceeded(Int)
  ConstraintLimitExceeded(Int)
  EmptyClockId
  EdgeVisitLimitExceeded(Int64)
  ArithmeticOverflow(phase~ : SolvePhase, constraint_index~ : Int)
  InvalidWitness
} derive(Debug, Eq)
