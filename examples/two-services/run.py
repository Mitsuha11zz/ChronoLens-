"""Capture two local TCP processes, convert logs, and optionally run MoonBit."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid

from convert import MAX_I64, convert_files, write_events

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent.parent
CREATE_FLAGS = getattr(subprocess, "CREATE_NO_WINDOW", 0)
CAPTURE_FILES = ("service-a.raw.jsonl", "service-b.raw.jsonl",
                 "events.original.jsonl", "events.shifted.jsonl")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def analyze_file(path: Path) -> tuple[dict, str]:
    moon = shutil.which("moon")
    if moon is None:
        raise ValueError("moon is required for --analyze or --replay")
    text = path.read_text(encoding="utf-8")
    if len(text.encode("utf-16-le")) // 2 > 24000:
        raise ValueError("sample exceeds the environment bridge limit; reduce --requests")
    environment = os.environ.copy()
    environment["CHRONOLENS_SAMPLE_INPUT"] = text
    completed = subprocess.run(
        [moon, "run", "examples/two-services/analyze", "--target", "native", "--deny-warn"],
        cwd=PROJECT, env=environment, capture_output=True, text=True,
        encoding="utf-8", errors="replace", timeout=45, creationflags=CREATE_FLAGS,
    )
    if completed.returncode:
        raise ValueError("MoonBit sample analysis failed:\n" + completed.stdout + completed.stderr)
    lines = [line for line in completed.stdout.splitlines()
             if line.startswith(("CAPTURE ", "RESULT "))]
    header, clocks = None, {}
    for line in lines:
        kind, payload = line.split(" ", 1)
        values = dict(token.split("=", 1) for token in payload.split())
        if kind == "CAPTURE":
            header = values
        else:
            clock = values.pop("clock")
            if clock in clocks:
                raise ValueError("duplicate clock in sample output")
            clocks[clock] = values
    if header is None or set(clocks) != {"A", "B"}:
        raise ValueError("unexpected MoonBit sample output")
    if (header["clocks"] != "2" or header["components"] != "1"
            or int(header["records"]) != 2 * int(header["pairs"])):
        raise ValueError("sample analysis did not cover all recorded messages")
    result = {"summary": header, "clocks": clocks}
    return result, "\n".join(lines) + "\n"


def analyze_pair(directory: Path, shift: int, expected_records: int) -> tuple[dict, dict]:
    original, original_output = analyze_file(directory / "events.original.jsonl")
    shifted, shifted_output = analyze_file(directory / "events.shifted.jsonl")
    for result in (original, shifted):
        if int(result["summary"]["records"]) != expected_records:
            raise ValueError("sample record count does not match its capture")
    base, changed = original["clocks"]["B"], shifted["clocks"]["B"]
    lower, upper = int(base["lower_us"]), int(base["upper_us"])
    shifted_lower, shifted_upper = int(changed["lower_us"]), int(changed["upper_us"])
    if not lower <= 0 <= upper:
        raise ValueError("same-host zero offset is not feasible; inspect wall-clock changes")
    if not shifted_lower <= -shift <= shifted_upper:
        raise ValueError("known injected offset is outside the computed range")
    if (shifted_lower, shifted_upper) != (lower - shift, upper - shift):
        raise ValueError("computed bounds did not translate by the injected offset")
    print("ORIGINAL\n" + original_output, end="")
    print("SHIFTED\n" + shifted_output, end="")
    return {
        "original": original,
        "shifted": shifted,
        "checks": {
            "same_host_zero_is_feasible": True,
            "known_injected_offset_is_feasible": True,
            "bounds_translate_exactly": True,
        },
    }, {"analysis.original.txt": original_output, "analysis.shifted.txt": shifted_output}


def capture(args) -> Path:
    run_id = uuid.uuid4().hex
    directory = (args.out or HERE / "runs" / run_id).resolve()
    directory.mkdir(parents=True, exist_ok=False)
    raw_a, raw_b = directory / CAPTURE_FILES[0], directory / CAPTURE_FILES[1]
    ready_path = directory / "ready.json"
    server = subprocess.Popen(
        [sys.executable, str(HERE / "service.py"), "--role", "B",
         "--raw", str(raw_b), "--ready", str(ready_path),
         "--requests", str(args.requests), "--processing-ms", str(args.processing_ms)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        encoding="utf-8", errors="replace", creationflags=CREATE_FLAGS,
    )
    try:
        deadline = time.monotonic() + 8
        while not ready_path.exists():
            if server.poll() is not None:
                _, errors = server.communicate()
                raise ValueError("service B failed before readiness: " + errors)
            if time.monotonic() >= deadline:
                raise ValueError("service B readiness timeout")
            time.sleep(0.02)
        # The file may become visible just before the writer closes it.
        while True:
            try:
                ready = json.loads(ready_path.read_text(encoding="utf-8"))
                break
            except json.JSONDecodeError:
                if time.monotonic() >= deadline:
                    raise ValueError("incomplete readiness record")
                time.sleep(0.02)
        caller = subprocess.run(
            [sys.executable, str(HERE / "service.py"), "--role", "A",
             "--raw", str(raw_a), "--port", str(ready["port"]),
             "--requests", str(args.requests), "--run-id", run_id],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=20, creationflags=CREATE_FLAGS,
        )
        if caller.returncode:
            raise ValueError("service A failed: " + caller.stderr)
        _, errors = server.communicate(timeout=10)
        if server.returncode:
            raise ValueError("service B failed: " + errors)
    finally:
        if server.poll() is None:
            server.terminate()
            server.communicate(timeout=5)
    original, processes = convert_files(raw_a, raw_b)
    shifted, _ = convert_files(raw_a, raw_b, b_shift_us=args.b_shift_us)
    if len(original) != 4 * args.requests:
        raise ValueError("capture did not record all request/response events")
    write_events(directory / CAPTURE_FILES[2], original)
    write_events(directory / CAPTURE_FILES[3], shifted)
    metadata = {
        "schema": "chronolens.two-services.capture.v1",
        "run_id": run_id,
        "transport": "TCP over 127.0.0.1",
        "same_host": True,
        "independent_process_ids": processes,
        "requests": args.requests,
        "events": len(original),
        "messages": 2 * args.requests,
        "requested_processing_ms": args.processing_ms,
        "clock_source": "time.time_ns() // 1000",
        "raw_capture_has_injected_offset": False,
        "b_timestamp_shift_us": str(args.b_shift_us),
        "known_injected_model_offset_b_us": str(-args.b_shift_us),
        "sha256": {name: digest(directory / name) for name in CAPTURE_FILES},
        "analysis": None,
    }
    # Keep the raw capture and its metadata even if the later analysis fails.
    manifest_path = directory / "manifest.json"
    with manifest_path.open("x", encoding="utf-8", newline="\n") as manifest:
        manifest.write(json.dumps(metadata, indent=2) + "\n")
    if args.analyze:
        metadata["analysis"], outputs = analyze_pair(directory, args.b_shift_us, len(original))
        for name, output in outputs.items():
            (directory / name).write_text(output, encoding="utf-8", newline="\n")
        manifest_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"Capture saved: {directory}")
    return directory


def replay(directory: Path) -> None:
    metadata = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
    if metadata["schema"] != "chronolens.two-services.capture.v1":
        raise ValueError("unknown archive schema")
    for name in CAPTURE_FILES:
        if digest(directory / name) != metadata["sha256"][name]:
            raise ValueError(f"archive hash mismatch: {name}")
    shift = int(metadata["b_timestamp_shift_us"])
    if not -MAX_I64 <= shift <= MAX_I64:
        raise ValueError("archive timestamp shift exceeds the example range")
    analyze_pair(directory, shift, metadata["events"])
    print("Archive replay completed without rewriting captured files.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--out", type=Path, help="new capture directory; existing directories are refused")
    mode.add_argument("--replay", type=Path, help="read-only replay of an archived capture")
    parser.add_argument("--requests", type=int, default=3)
    parser.add_argument("--processing-ms", type=int, default=10)
    parser.add_argument("--b-shift-us", type=int, default=-120000)
    parser.add_argument("--analyze", action="store_true", help="run the MoonBit sample adapter after capture")
    args = parser.parse_args()
    if not 1 <= args.requests <= 16 or not 0 <= args.processing_ms <= 200:
        parser.error("requests must be 1..16 and processing-ms must be 0..200")
    if not -MAX_I64 <= args.b_shift_us <= MAX_I64:
        parser.error("timestamp shift must have a representable Int64 opposite")
    if args.replay:
        replay(args.replay.resolve())
    else:
        capture(args)


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    main()
