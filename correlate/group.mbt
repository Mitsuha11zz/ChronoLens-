///|
priv struct Bucket {
  sends : Array[@model.Event]
  receives : Array[@model.Event]
}

///|
fn compare_keys(left : @model.MessageKey, right : @model.MessageKey) -> Int {
  let trace_order = left.trace_id().compare(right.trace_id())
  if trace_order != 0 {
    return trace_order
  }
  let message_order = left.message_id().compare(right.message_id())
  if message_order != 0 {
    return message_order
  }
  left.attempt().compare(right.attempt())
}

///|
fn validate_limit(max_events : Int, count : Int) -> Unit raise CorrelationError {
  if max_events <= 0 || max_events > 1000000 {
    raise InvalidEventLimit
  }
  if count > max_events {
    raise EventLimitExceeded(limit=max_events, count~)
  }
}

///|
/// Correlate immutable typed events. No timestamp ordering or clock matching
/// is used to choose a pair. Duplicate event IDs reject the entire collection.
pub fn correlate(
  events : ArrayView[@model.Event],
  max_events? : Int = 10000,
) -> CorrelationReport raise CorrelationError {
  validate_limit(max_events, events.length())
  let ids : Map[String, Unit] = Map([])
  for event in events {
    if ids.contains(event.event_id()) {
      raise DuplicateEventId(event.event_id())
    }
    ids[event.event_id()] = ()
  }
  let groups : Map[@model.MessageKey, Bucket] = Map([])
  for event in events {
    let key = event.key()
    let bucket = match groups.get(key) {
      Some(bucket) => bucket
      None => {
        let bucket = { sends: [], receives: [], }
        groups[key] = bucket
        bucket
      }
    }
    match event.kind() {
      @model.Send => bucket.sends.push(event)
      @model.Receive => bucket.receives.push(event)
    }
  }
  let keys : Array[@model.MessageKey] = []
  for key, _ in groups {
    keys.push(key)
  }
  keys.sort_by(compare_keys)
  let pairs : Array[MessagePair] = []
  let unresolved : Array[UnresolvedGroup] = []
  let mut missing_groups = 0
  let mut ambiguous_groups = 0
  for key in keys {
    let bucket = groups[key]
    bucket.sends.sort_by((a, b) => a.event_id().compare(b.event_id()))
    bucket.receives.sort_by((a, b) => a.event_id().compare(b.event_id()))
    let sends = bucket.sends.length()
    let receives = bucket.receives.length()
    if sends == 1 && receives == 1 {
      pairs.push({
        key,
        send_event: bucket.sends[0],
        receive_event: bucket.receives[0],
      })
    } else {
      let issues : Array[CorrelationIssueKind] = []
      if sends == 0 {
        issues.push(MissingSend)
      }
      if receives == 0 {
        issues.push(MissingReceive)
      }
      if sends == 0 || receives == 0 {
        missing_groups += 1
      }
      if sends > 1 || receives > 1 {
        issues.push(Ambiguous)
        ambiguous_groups += 1
      }
      unresolved.push({
        key,
        send_events: ReadOnlyArray::from_array(bucket.sends),
        receive_events: ReadOnlyArray::from_array(bucket.receives),
        issues: ReadOnlyArray::from_array(issues),
      })
    }
  }
  {
    pairs: ReadOnlyArray::from_array(pairs),
    unresolved: ReadOnlyArray::from_array(unresolved),
    stats: {
      total_events: events.length(),
      group_count: keys.length(),
      paired_groups: pairs.length(),
      unresolved_groups: unresolved.length(),
      missing_groups,
      ambiguous_groups,
    },
  }
}
