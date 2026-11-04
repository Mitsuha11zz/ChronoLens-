"""Serve the local ChronoLens workbench and forward analyses to the MoonBit CLI."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit


ROOT = Path(__file__).resolve().parents[1]
DEMO = Path(__file__).resolve().parent
MAX_INPUT_BYTES = 8 * 1024 * 1024
MAX_PRIOR_FILE_BYTES = 1024 * 1024
MAX_BODY_BYTES = MAX_INPUT_BYTES * 2 + MAX_PRIOR_FILE_BYTES + 64 * 1024
MAX_REFERENCE_CLOCK_CHARS = 4096
MAX_PRIORS = 64
MAX_PRIOR_TEXT_CHARS = 4096
ANALYSIS_TIMEOUT_SECONDS = 120
ANALYSIS_LOCK = threading.Lock()

SAMPLES = {
    "four-events": ("可行区间 · 四事件", ROOT / "fixtures" / "four-events.jsonl"),
    "negative-cycle": ("负环冲突 · 直接矛盾", ROOT / "fixtures" / "negative-cycle.jsonl"),
    "mixed-associations": (
        "关联缺口 · 缺失与歧义",
        ROOT / "fixtures" / "mixed-associations.jsonl",
    ),
    "component-analysis": (
        "多分量 · 独立坐标",
        ROOT / "fixtures" / "component-analysis.jsonl",
    ),
}

STATIC_FILES = {
    "/": (DEMO / "index.html", "text/html; charset=utf-8"),
    "/app.js": (DEMO / "app.js", "text/javascript; charset=utf-8"),
    "/style.css": (DEMO / "style.css", "text/css; charset=utf-8"),
}


def engine_path() -> Path:
    for profile in ("debug", "release"):
        package_dir = (
            ROOT / "_build" / "native" / profile / "build" / "cmd" / "chronolens"
        )
        for executable in ("chronolens.exe", "chronolens"):
            candidate = package_dir / executable
            if candidate.is_file():
                return candidate
    raise RuntimeError("MoonBit native CLI binary was not found under _build/native.")


def build_engine() -> Path:
    moon = shutil.which("moon")
    if moon is None:
        raise RuntimeError("找不到 MoonBit 工具链 moon，请先安装并加入 PATH。")

    subprocess.run(
        [moon, "build", "cmd/chronolens", "--target", "native", "--deny-warn"],
        cwd=ROOT,
        check=True,
    )
    return engine_path()


ENGINE: Path | None = None


def json_bytes(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def decimal_nonnegative(value: object) -> str | None:
    if isinstance(value, bool):
        return None
    text = str(value)
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)", text):
        return None
    if len(text) > 19 or (len(text) == 19 and text > "9223372036854775807"):
        return None
    return text


def decimal_int64(value: object) -> str | None:
    if not isinstance(value, str) or not re.fullmatch(r"-?(?:0|[1-9][0-9]*)", value):
        return None
    if len(value) > 20:
        return None
    parsed = int(value)
    if parsed < -(1 << 63) or parsed > (1 << 63) - 1:
        return None
    return value


def validate_priors(value: object) -> tuple[list[dict[str, str | None]], str | None]:
    if value is None:
        return [], None
    if not isinstance(value, list):
        return [], "相对偏移先验必须是数组。"
    if len(value) > MAX_PRIORS:
        return [], f"单次演示最多接受 {MAX_PRIORS} 条先验。"

    allowed_fields = {"clock_id", "reference_clock", "label", "lower_us", "upper_us"}
    labels: set[str] = set()
    priors: list[dict[str, str | None]] = []
    for index, item in enumerate(value, start=1):
        if not isinstance(item, dict):
            return [], f"第 {index} 条先验必须是对象。"
        unknown = set(item) - allowed_fields
        if unknown:
            return [], f"第 {index} 条先验包含未知字段：{sorted(unknown)[0]}。"

        text_fields: dict[str, str] = {}
        for name in ("clock_id", "reference_clock", "label"):
            raw = item.get(name)
            if not isinstance(raw, str):
                return [], f"第 {index} 条先验缺少文本字段 {name}。"
            cleaned = raw.strip()
            if not cleaned or len(cleaned) > MAX_PRIOR_TEXT_CHARS:
                return [], f"第 {index} 条先验的 {name} 为空或过长。"
            text_fields[name] = cleaned

        label = text_fields["label"]
        if label in labels:
            return [], f"先验标签必须唯一：{label}。"
        labels.add(label)

        bounds: dict[str, str | None] = {}
        for name in ("lower_us", "upper_us"):
            raw = item.get(name)
            if raw is None:
                bounds[name] = None
                continue
            parsed = decimal_int64(raw)
            if parsed is None:
                return [], f"第 {index} 条先验的 {name} 必须是十进制 Int64 字符串。"
            bounds[name] = parsed

        lower = bounds["lower_us"]
        upper = bounds["upper_us"]
        if lower is None and upper is None:
            return [], f"第 {index} 条先验至少要设置一个边界。"
        if lower is not None and upper is not None and int(lower) > int(upper):
            return [], f"第 {index} 条先验的下界不能大于上界。"

        priors.append({**text_fields, **bounds})
    serialized_size = len(json.dumps(priors, ensure_ascii=False).encode("utf-8"))
    if serialized_size > MAX_PRIOR_FILE_BYTES:
        return [], "先验数据超过 CLI 的 1 MiB 文件限制。"
    return priors, None


class Handler(BaseHTTPRequestHandler):
    server_version = "ChronoLensLocal/1.0"

    def end_headers(self) -> None:
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Cache-Control", "no-store")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; script-src 'self'; style-src 'self'; "
            "connect-src 'self'; img-src 'self' data:; object-src 'none'; "
            "base-uri 'none'; frame-ancestors 'none'",
        )
        super().end_headers()

    def send_bytes(self, body: bytes, content_type: str, status: int = 200) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_json(self, value: object, status: int = 200) -> None:
        self.send_bytes(json_bytes(value), "application/json; charset=utf-8", status)

    def do_GET(self) -> None:
        request = urlsplit(self.path)
        if request.path in STATIC_FILES:
            path, content_type = STATIC_FILES[request.path]
            try:
                body = path.read_bytes()
            except OSError:
                self.send_json({"error": "演示文件不可用。"}, 500)
                return
            self.send_bytes(body, content_type)
            return

        if request.path == "/api/samples":
            samples = [
                {"id": sample_id, "label": label}
                for sample_id, (label, _) in SAMPLES.items()
            ]
            self.send_json({"samples": samples})
            return

        if request.path == "/api/sample":
            sample_id = parse_qs(request.query).get("id", [""])[0]
            sample = SAMPLES.get(sample_id)
            if sample is None:
                self.send_json({"error": "未知的内置样例。"}, 404)
                return
            label, path = sample
            try:
                text = path.read_text(encoding="utf-8")
            except (OSError, UnicodeError):
                self.send_json({"error": "内置样例读取失败。"}, 500)
                return
            self.send_json({"id": sample_id, "label": label, "jsonl": text})
            return

        self.send_json({"error": "未找到此页面。"}, 404)

    def do_POST(self) -> None:
        if urlsplit(self.path).path != "/api/analyze":
            self.send_json({"error": "未找到此接口。"}, 404)
            return

        content_type = self.headers.get_content_type()
        if content_type != "application/json":
            self.send_json({"error": "请求必须使用 application/json。"}, 415)
            return

        try:
            length = int(self.headers.get("Content-Length", "-1"))
        except ValueError:
            self.send_json({"error": "请求长度无效。"}, 400)
            return
        if length < 0 or length > MAX_BODY_BYTES:
            self.send_json({"error": "请求超过本地演示服务的大小限制。"}, 413)
            return

        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
        except (UnicodeError, json.JSONDecodeError):
            self.send_json({"error": "请求不是有效的 UTF-8 JSON。"}, 400)
            return
        if not isinstance(payload, dict) or not isinstance(payload.get("jsonl"), str):
            self.send_json({"error": "请求缺少 JSONL 文本。"}, 400)
            return

        tolerance = decimal_nonnegative(payload.get("relation_tolerance_us", "0"))
        if tolerance is None:
            self.send_json({"error": "关系容差必须是非负 Int64 十进制整数。"}, 400)
            return

        reference_clock = payload.get("reference_clock", "")
        if not isinstance(reference_clock, str) or len(reference_clock) > MAX_REFERENCE_CLOCK_CHARS:
            self.send_json({"error": "参考时钟标识无效或过长。"}, 400)
            return

        priors, prior_error = validate_priors(payload.get("priors", []))
        if prior_error is not None:
            self.send_json({"error": prior_error}, 400)
            return

        if ENGINE is None:
            self.send_json({"error": "MoonBit CLI 尚未准备好。"}, 503)
            return

        try:
            response = self.run_analysis(
                payload["jsonl"], tolerance, reference_clock.strip(), priors
            )
        except subprocess.TimeoutExpired:
            self.send_json({"error": "分析超过 120 秒，已停止本次请求。"}, 504)
            return
        except (OSError, RuntimeError) as error:
            self.send_json({"error": f"本机分析失败：{error}"}, 500)
            return

        self.send_json(response)

    def run_analysis(
        self,
        jsonl: str,
        tolerance: str,
        reference_clock: str,
        priors: list[dict[str, str | None]],
    ) -> dict[str, object]:
        assert ENGINE is not None
        with tempfile.TemporaryDirectory(prefix="chronolens-demo-") as temp_dir:
            input_path = Path(temp_dir) / "events.jsonl"
            input_path.write_bytes(jsonl.encode("utf-8"))
            arguments = [
                str(ENGINE),
                "events.jsonl",
                "--format",
                "json",
                "--relation-tolerance-us",
                tolerance,
            ]
            if reference_clock:
                arguments.extend(["--reference-clock", reference_clock])
            if priors:
                priors_path = Path(temp_dir) / "priors.json"
                priors_path.write_bytes(
                    json.dumps(priors, ensure_ascii=False).encode("utf-8")
                )
                arguments.extend(["--priors-file", priors_path.name])

            with ANALYSIS_LOCK:
                completed = subprocess.run(
                    arguments,
                    cwd=temp_dir,
                    capture_output=True,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    timeout=ANALYSIS_TIMEOUT_SECONDS,
                    check=False,
                )

        try:
            report = json.loads(completed.stdout)
        except json.JSONDecodeError as error:
            detail = completed.stderr.strip() or "MoonBit CLI 没有返回诊断 JSON。"
            raise RuntimeError(detail) from error
        if not isinstance(report, dict):
            raise RuntimeError("MoonBit CLI 返回了非对象诊断报告。")
        if completed.returncode not in (0, 1, 4, 5):
            detail = completed.stderr.strip() or f"MoonBit CLI 退出码：{completed.returncode}"
            raise RuntimeError(detail)
        return {"exit_code": completed.returncode, "report": report}


def main() -> int:
    global ENGINE
    try:
        ENGINE = build_engine()
    except (OSError, subprocess.CalledProcessError, RuntimeError) as error:
        print(f"ChronoLens demo: {error}", file=sys.stderr)
        return 1

    server = ThreadingHTTPServer(("127.0.0.1", 8765), Handler)
    print("ChronoLens demo is ready at http://127.0.0.1:8765")
    print("The server binds only to 127.0.0.1; input stays on this machine.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nChronoLens demo stopped.")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
