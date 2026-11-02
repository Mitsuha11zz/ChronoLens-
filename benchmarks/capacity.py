"""Measure end-to-end native CLI time on deterministic paired-event inputs."""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MESSAGES = (100, 1_000, 5_000)
MAX_MESSAGES = 5_000


def parse_messages(value: str) -> tuple[int, ...]:
    try:
        messages = tuple(int(part.strip()) for part in value.split(","))
    except ValueError as error:
        raise argparse.ArgumentTypeError(
            "消息规模必须是逗号分隔的正整数。"
        ) from error

    if not messages or any(count < 1 or count > MAX_MESSAGES for count in messages):
        raise argparse.ArgumentTypeError(
            f"每档消息数必须在 1 到 {MAX_MESSAGES} 之间。"
        )
    if len(set(messages)) != len(messages):
        raise argparse.ArgumentTypeError("消息规模不能重复。")
    return messages


def build_engine() -> Path:
    moon = shutil.which("moon")
    if moon is None:
        raise RuntimeError("找不到 MoonBit 工具链 moon，请先安装并加入 PATH。")

    completed = subprocess.run(
        [moon, "build", "cmd/chronolens", "--target", "native", "--deny-warn"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise RuntimeError(detail or f"MoonBit 构建退出码为 {completed.returncode}。")
    executable = "chronolens.exe" if os.name == "nt" else "chronolens"
    engine = (
        ROOT / "_build" / "native" / "debug" / "build" / "cmd" / "chronolens" / executable
    )
    if not engine.is_file():
        raise RuntimeError("MoonBit 构建完成，但没有找到 native CLI 可执行文件。")
    return engine


def write_workload(path: Path, message_count: int) -> int:
    with path.open("w", encoding="utf-8", newline="\n") as output:
        for index in range(message_count):
            suffix = f"{index:08d}"
            send_time = index * 1_000_000
            receive_time = send_time + 120_000
            common = {
                "attempt": 0,
                "trace_id": f"trace-{suffix}",
                "message_id": f"message-{suffix}",
            }
            send = {
                **common,
                "event_id": f"send-{suffix}",
                "clock_id": "service-a",
                "kind": "send",
                "ts_us": str(send_time),
            }
            receive = {
                **common,
                "event_id": f"receive-{suffix}",
                "clock_id": "service-b",
                "kind": "receive",
                "ts_us": str(receive_time),
            }
            output.write(json.dumps(send, separators=(",", ":")) + "\n")
            output.write(json.dumps(receive, separators=(",", ":")) + "\n")
    return path.stat().st_size


def analyze_once(engine: Path, input_path: Path, report_path: Path) -> float:
    started = time.perf_counter()
    completed = subprocess.run(
        [
            str(engine),
            str(input_path),
            "--format",
            "json",
            "--output",
            str(report_path),
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    elapsed = time.perf_counter() - started

    if completed.returncode != 0:
        detail = completed.stderr.strip() or f"CLI 退出码为 {completed.returncode}。"
        raise RuntimeError(f"ChronoLens 分析失败：{detail}")

    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise RuntimeError("CLI 没有写出有效的 JSON 诊断报告。") from error

    components = report.get("components") if isinstance(report, dict) else None
    component = components[0] if isinstance(components, list) and len(components) == 1 else None
    if (
        not isinstance(report, dict)
        or report.get("has_conflicts") is not False
        or not isinstance(component, dict)
        or component.get("status") != "feasible"
    ):
        raise RuntimeError("基准输入没有得到预期的单个可行分量报告。")
    return elapsed


def run_case(
    engine: Path,
    message_count: int,
    repeats: int,
    warmups: int,
    temp_dir: Path,
) -> dict[str, object]:
    input_path = temp_dir / f"events-{message_count}.jsonl"
    input_bytes = write_workload(input_path, message_count)

    for index in range(warmups):
        report_path = temp_dir / f"warmup-{message_count}-{index}.json"
        analyze_once(engine, input_path, report_path)

    samples = []
    for index in range(repeats):
        report_path = temp_dir / f"report-{message_count}-{index}.json"
        samples.append(analyze_once(engine, input_path, report_path))
    median_seconds = statistics.median(samples)
    event_count = message_count * 2
    return {
        "messages": message_count,
        "events": event_count,
        "clock_domains": 2,
        "components": 1,
        "input_bytes": input_bytes,
        "samples_seconds": [round(sample, 6) for sample in samples],
        "median_seconds": round(median_seconds, 6),
        "events_per_second": round(event_count / median_seconds, 2),
    }


def positive_int(value: str) -> int:
    try:
        parsed = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("值必须是整数。") from error
    if parsed < 1:
        raise argparse.ArgumentTypeError("值必须大于零。")
    return parsed


def nonnegative_int(value: str) -> int:
    try:
        parsed = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("值必须是整数。") from error
    if parsed < 0:
        raise argparse.ArgumentTypeError("值不能小于零。")
    return parsed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--messages",
        type=parse_messages,
        default=DEFAULT_MESSAGES,
        help="逗号分隔的每档消息数（默认：100,1000,5000）。",
    )
    parser.add_argument(
        "--repeats",
        type=positive_int,
        default=3,
        help="每档测量次数（默认：3）。",
    )
    parser.add_argument(
        "--warmups",
        type=nonnegative_int,
        default=1,
        help="每档预热次数（默认：1）。",
    )
    parser.add_argument(
        "--binary",
        type=Path,
        help="已有 native CLI 路径；省略时先构建项目。",
    )
    args = parser.parse_args()
    if args.binary is not None:
        args.binary = args.binary.resolve()
        if not args.binary.is_file():
            parser.error("--binary 指向的文件不存在。")
    return args


def main() -> int:
    args = parse_args()
    try:
        engine = args.binary if args.binary is not None else build_engine()
        with tempfile.TemporaryDirectory(prefix="chronolens-benchmark-") as workdir:
            temp_dir = Path(workdir)
            cases = [
                run_case(engine, count, args.repeats, args.warmups, temp_dir)
                for count in args.messages
            ]
    except (OSError, RuntimeError) as error:
        print(f"ChronoLens benchmark: {error}", file=sys.stderr)
        return 1

    result = {
        "format": "chronolens.capacity-benchmark.v1",
        "platform": platform.system(),
        "python": platform.python_version(),
        "binary": engine.name,
        "timing_scope": (
            "CLI process startup, file read, analysis, report serialization and write; "
            "excludes build and input generation"
        ),
        "warmups_per_case": args.warmups,
        "repeats_per_case": args.repeats,
        "cases": cases,
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
