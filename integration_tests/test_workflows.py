"""End-to-end regression checks for the OTLP and local demo workflows."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
ENGINE = (
    ROOT
    / "_build"
    / "native"
    / "debug"
    / "build"
    / "cmd"
    / "chronolens"
    / ("chronolens.exe" if os.name == "nt" else "chronolens")
)
CONVERTER = ROOT / "examples" / "otel-rpc" / "convert.py"
OTLP_SAMPLE = ROOT / "examples" / "otel-rpc" / "sample-traces.json"

if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from demo import server as demo_server  # noqa: E402


def build_engine() -> Path:
    moon = shutil.which("moon")
    if moon is None:
        raise RuntimeError("MoonBit 工具链 moon 必须已安装并加入 PATH。")

    completed = subprocess.run(
        [moon, "build", "cmd/chronolens", "--target", "native", "--deny-warn"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise RuntimeError(detail or f"MoonBit 构建退出码为 {completed.returncode}。")
    if not ENGINE.is_file():
        raise RuntimeError("MoonBit 构建完成，但没有找到 native CLI 可执行文件。")
    return ENGINE


class QuietDemoHandler(demo_server.Handler):
    def log_message(self, format: str, *args: object) -> None:
        del format, args


class WorkflowIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.engine = build_engine()

    def test_otlp_sample_converts_and_runs_through_cli(self) -> None:
        with tempfile.TemporaryDirectory(prefix="chronolens-otel-test-") as workdir:
            events_path = Path(workdir) / "events.jsonl"
            converted = subprocess.run(
                [
                    sys.executable,
                    str(CONVERTER),
                    str(OTLP_SAMPLE),
                    "--output",
                    str(events_path),
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                check=False,
            )
            self.assertEqual(0, converted.returncode, converted.stderr)

            event_rows = [
                json.loads(line)
                for line in events_path.read_text(encoding="utf-8").splitlines()
                if line.strip()
            ]
            self.assertEqual(4, len(event_rows))
            self.assertEqual(4, len({row["event_id"] for row in event_rows}))

            analyzed = subprocess.run(
                [str(self.engine), str(events_path), "--format", "json"],
                cwd=ROOT,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                check=False,
            )
            self.assertEqual(0, analyzed.returncode, analyzed.stderr)
            report = json.loads(analyzed.stdout)
            self.assertIs(report["has_conflicts"], False)
            self.assertEqual(1, len(report["components"]))
            self.assertEqual("feasible", report["components"][0]["status"])

    def test_demo_sample_endpoint_runs_analysis_through_cli(self) -> None:
        previous_engine = demo_server.ENGINE
        demo_server.ENGINE = self.engine
        httpd = ThreadingHTTPServer(("127.0.0.1", 0), QuietDemoHandler)
        thread = threading.Thread(target=httpd.serve_forever, daemon=True)
        thread.start()
        base_url = f"http://127.0.0.1:{httpd.server_address[1]}"
        try:
            with urlopen(f"{base_url}/api/samples", timeout=5) as response:
                samples = json.loads(response.read().decode("utf-8"))["samples"]
            self.assertIn("four-events", {sample["id"] for sample in samples})

            with urlopen(
                f"{base_url}/api/sample?id=four-events", timeout=5
            ) as response:
                sample = json.loads(response.read().decode("utf-8"))
            self.assertEqual("four-events", sample["id"])
            self.assertEqual(4, len(sample["jsonl"].splitlines()))

            request_body = json.dumps(
                {"jsonl": sample["jsonl"], "relation_tolerance_us": "0"}
            ).encode("utf-8")
            request = Request(
                f"{base_url}/api/analyze",
                data=request_body,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urlopen(request, timeout=10) as response:
                result = json.loads(response.read().decode("utf-8"))

            self.assertEqual(0, result["exit_code"])
            report = result["report"]
            self.assertIs(report["has_conflicts"], False)
            self.assertEqual(1, len(report["components"]))
            self.assertEqual("feasible", report["components"][0]["status"])
            self.assertEqual(2, report["coverage"]["paired_groups"])
        finally:
            httpd.shutdown()
            httpd.server_close()
            thread.join(timeout=5)
            demo_server.ENGINE = previous_engine


if __name__ == "__main__":
    unittest.main()
