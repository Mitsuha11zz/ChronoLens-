///|
/// An explicit assumption: lower <= offset(clock) - offset(reference) <= upper.
/// At least one bound is required. The label must be unique within a build.
pub struct OffsetPrior {
  clock_id : String
  reference_clock : String
  lower_us : Int64?
  upper_us : Int64?
  label : String
} derive(Debug, Eq)

///|
pub(all) suberror ConstraintBuildError {
  InvalidTolerance
  InvalidPriorField(String)
  EmptyPriorBounds(String)
  InvertedPriorRange(String)
  DuplicatePriorLabel(String)
  InvalidConstraintLimit
  ConstraintLimitExceeded(Int)
  ArithmeticOverflow(@model.ConstraintOrigin)
} derive(Debug, Eq)

///|
/// Each edge carries either the original paired events or an explicit prior.
pub(all) enum ConstraintEvidence {
  Message(pair~ : @correlate.MessagePair, tolerance_us~ : Int64)
  Prior(prior~ : OffsetPrior, lower_bound~ : Bool)
} derive(Debug, Eq)

///|
pub struct BuiltConstraint {
  constraint : @model.DifferenceConstraint
  evidence : ConstraintEvidence
} derive(Debug, Eq)

///|
/// No feasibility verdict is made here. Correlation evidence is retained even
/// when missing or ambiguous groups contribute no edges.
pub struct ConstraintSet {
  clocks : ReadOnlyArray[String]
  constraints : ReadOnlyArray[BuiltConstraint]
  correlation : @correlate.CorrelationReport
  relation_tolerance_us : Int64
} derive(Debug, Eq)

///|
#deprecated
pub extend OffsetPrior with @debug.Debug::{to_repr}

///|
#deprecated
pub extend OffsetPrior with Eq::{equal, not_equal}

///|
#deprecated
pub extend ConstraintBuildError with @debug.Debug::{to_repr}

///|
#deprecated
pub extend ConstraintBuildError with Eq::{equal, not_equal}

///|
#deprecated
pub extend ConstraintEvidence with @debug.Debug::{to_repr}

///|
#deprecated
pub extend ConstraintEvidence with Eq::{equal, not_equal}

///|
#deprecated
pub extend BuiltConstraint with @debug.Debug::{to_repr}

///|
#deprecated
pub extend BuiltConstraint with Eq::{equal, not_equal}

///|
#deprecated
pub extend ConstraintSet with @debug.Debug::{to_repr}

///|
#deprecated
pub extend ConstraintSet with Eq::{equal, not_equal}
