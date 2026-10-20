"""Convert this example's explicit RPC records to ChronoLens JSONL."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re

MIN_I64 = -(1 << 63)
MAX_I64 = (1 << 63) - 1
SCHEMA = "chronolens.local-rpc.v1"
FIELDS = {"schema", "service", "process_id", "phase", "trace_id",
          "message_id", "attempt", "ts_unix_us"}
PHASES = {
    "request_send": ("A", "send"),
    "request_receive": ("B", "receive"),
    "response_send": ("B", "send"),
    "response_receive": ("A", "receive"),
}


def reject_constant(value):
    raise ValueError(f"non-JSON numeric constant: {value}")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON field: {key}")
        result[key] = value
    return result


def exact_i64(text: str) -> int:
    if not isinstance(text, str) or re.fullmatch(r"-?(0|[1-9][0-9]*)", text) is None:
        raise ValueError("timestamp must be an exact decimal integer string")
    value = int(text)
    if not MIN_I64 <= value <= MAX_I64:
        raise ValueError("timestamp exceeds Int64")
    return value


def load_raw(path: Path, service: str) -> list[tuple[int, dict]]:
    if path.stat().st_size > 8 * 1024 * 1024:
        raise ValueError("raw file exceeds the 8 MiB example limit")
    records = []
    process_ids = set()
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        record = json.loads(line, object_pairs_hook=unique_object, parse_constant=reject_constant)
        if not isinstance(record, dict) or set(record) != FIELDS:
            raise ValueError(f"{path.name}:{line_number}: unexpected record fields")
        phase = record["phase"]
        if (record["schema"] != SCHEMA or record["service"] != service
                or not isinstance(phase, str) or PHASES.get(phase, (None,))[0] != service):
            raise ValueError(f"{path.name}:{line_number}: unexpected service or phase")
        if type(record["attempt"]) is not int or record["attempt"] != 0:
            raise ValueError("this capture format supports attempt=0 only")
        if type(record["process_id"]) is not int or record["process_id"] <= 0:
            raise ValueError("invalid process identity")
        process_ids.add(record["process_id"])
        for key in ("trace_id", "message_id"):
            if not isinstance(record[key], str) or re.fullmatch(r"[A-Za-z0-9_.-]{1,160}", record[key]) is None:
                raise ValueError(f"invalid explicit {key}")
        exact_i64(record["ts_unix_us"])
        records.append((line_number, record))
    if not records or len(process_ids) != 1:
        raise ValueError("each raw file must contain one nonempty process capture")
    return records


def convert_files(raw_a: Path, raw_b: Path, *, b_shift_us: int = 0) -> tuple[list[dict], dict]:
    if type(b_shift_us) is not int or not MIN_I64 <= b_shift_us <= MAX_I64:
        raise ValueError("B timestamp shift exceeds Int64")
    if raw_a.resolve() == raw_b.resolve() or raw_a.name == raw_b.name:
        raise ValueError("raw files must have distinct paths and source names")
    events, process_ids, ids = [], {}, set()
    for service, path in (("A", raw_a), ("B", raw_b)):
        records = load_raw(path, service)
        process_ids[service] = records[0][1]["process_id"]
        for line_number, record in records:
            _, kind = PHASES[record["phase"]]
            timestamp = exact_i64(record["ts_unix_us"]) + (b_shift_us if service == "B" else 0)
            if not MIN_I64 <= timestamp <= MAX_I64:
                raise ValueError("shifted timestamp exceeds Int64")
            event_id = f"{service}:{record['trace_id']}:{record['message_id']}:{kind}"
            if event_id in ids:
                raise ValueError("duplicate source event")
            ids.add(event_id)
            events.append({
                "event_id": event_id,
                "clock_id": service,
                "trace_id": record["trace_id"],
                "message_id": record["message_id"],
                "attempt": record["attempt"],
                "kind": kind,
                "ts_us": str(timestamp),
                "source": {"path": path.name, "line": line_number},
            })
    if process_ids["A"] == process_ids["B"]:
        raise ValueError("the local example requires two independent processes")
    return events, process_ids


def write_events(path: Path, events: list[dict]) -> None:
    # Validation is complete before creating the output; existing files are refused.
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        for event in events:
            stream.write(json.dumps(event, separators=(",", ":"), ensure_ascii=False) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-a", type=Path, required=True)
    parser.add_argument("--raw-b", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--b-shift-us", type=int, default=0)
    args = parser.parse_args()
    events, _ = convert_files(args.raw_a, args.raw_b, b_shift_us=args.b_shift_us)
    write_events(args.out, events)
    print(f"Converted {len(events)} events to {args.out}")


if __name__ == "__main__":
    main()
