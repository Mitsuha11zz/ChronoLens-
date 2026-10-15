///|
pub fn OffsetPrior::new(
  clock_id~ : String,
  reference_clock~ : String,
  label~ : String,
  lower_us? : Int64,
  upper_us? : Int64,
) -> OffsetPrior raise ConstraintBuildError {
  // Reuse the model's identifier contract, without normalizing evidence.
  ignore(
    @model.DifferenceConstraint::new(
      left_clock=clock_id,
      right_clock=reference_clock,
      upper_bound_us=0L,
      origin=Prior(label~),
    ),
  ) catch {
    @model.ModelError::EmptyIdentifier(field) => raise InvalidPriorField(field)
    _ => raise InvalidPriorField("prior")
  }
  if lower_us is None && upper_us is None {
    raise EmptyPriorBounds(label)
  }
  match (lower_us, upper_us) {
    (Some(lower), Some(upper)) =>
      if lower > upper {
        raise InvertedPriorRange(label)
      }
    _ => ()
  }
  { clock_id, reference_clock, lower_us, upper_us, label, }
}
