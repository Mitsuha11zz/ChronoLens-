///|
test "constraint comparison agrees with bigint on 343 boundary combinations" {
  let values = [
    @int64.MIN_VALUE,
    @int64.MIN_VALUE + 1L,
    -1L,
    0L,
    1L,
    @int64.MAX_VALUE - 1L,
    @int64.MAX_VALUE,
  ]
  for left in values {
    for right in values {
      for weight in values {
        let exact = @bigint.BigInt::from_int64(right) +
          @bigint.BigInt::from_int64(weight)
        let expected = exact.compare_int64(left) >= 0
        assert_eq(satisfies_constraint(left, right, weight), expected)
      }
    }
  }
}

///|
test "cycle sum agrees with bigint despite cancelling intermediate extremes" {
  let values = [
    @int64.MIN_VALUE,
    @int64.MIN_VALUE + 1L,
    -1L,
    0L,
    1L,
    @int64.MAX_VALUE - 1L,
    @int64.MAX_VALUE,
  ]
  for a in values {
    for b in values {
      for c in values {
        let exact = @bigint.BigInt::from_int64(a) +
          @bigint.BigInt::from_int64(b) +
          @bigint.BigInt::from_int64(c)
        let fits = exact.compare_int64(@int64.MIN_VALUE) >= 0 &&
          exact.compare_int64(@int64.MAX_VALUE) <= 0
        let edges = [
          IndexedEdge::{ from: 0, to: 0, index: 0, weight: a, },
          IndexedEdge::{ from: 0, to: 0, index: 1, weight: b, },
          IndexedEdge::{ from: 0, to: 0, index: 2, weight: c, },
        ]
        let budget = Budget::{ limit: 100L, used: 0L, passes: 0, }
        try sum_cycle_weights(edges, budget) catch {
          ArithmeticOverflow(phase~, ..) => {
            assert_true(!fits)
            assert_eq(phase, CycleWeightSum)
          }
          _ => fail("unexpected non-arithmetic error")
        } noraise {
          total => {
            assert_true(fits)
            assert_eq(total, exact.to_int64())
          }
        }
      }
    }
  }
}

///|
test "coordinate subtraction agrees with bigint for all 49 extreme pairs" {
  let values = [
    @int64.MIN_VALUE,
    @int64.MIN_VALUE + 1L,
    -1L,
    0L,
    1L,
    @int64.MAX_VALUE - 1L,
    @int64.MAX_VALUE,
  ]
  for value in values {
    for reference in values {
      let exact = @bigint.BigInt::from_int64(value) -
        @bigint.BigInt::from_int64(reference)
      let fits = exact.compare_int64(@int64.MIN_VALUE) >= 0 &&
        exact.compare_int64(@int64.MAX_VALUE) <= 0
      try relative_offset(value, reference, "clock", "reference") catch {
        error => {
          assert_true(!fits)
          assert_eq(
            error,
            OffsetOverflow(clock_id="clock", reference_clock="reference"),
          )
        }
      } noraise {
        offset => {
          assert_true(fits)
          assert_eq(offset, exact.to_int64())
        }
      }
    }
  }
}
