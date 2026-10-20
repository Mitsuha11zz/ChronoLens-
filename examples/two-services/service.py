"""Two independent local RPC roles. Python standard library only."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import socket
import time

SCHEMA = "chronolens.local-rpc.v1"
MAX_FRAME = 8192


def send_packet(connection: socket.socket, packet: dict) -> None:
    connection.sendall((json.dumps(packet, separators=(",", ":")) + "\n").encode("utf-8"))


def receive_packet(stream) -> dict:
    data = stream.readline(MAX_FRAME + 1)
    if not data or len(data) > MAX_FRAME or not data.endswith(b"\n"):
        raise ValueError("missing or oversized RPC frame")
    packet = json.loads(data.decode("utf-8"))
    if not isinstance(packet, dict):
        raise ValueError("RPC frame must be an object")
    return packet


class Recorder:
    def __init__(self, path: Path, service: str):
        self.file = path.open("x", encoding="utf-8", newline="\n")
        self.service = service

    def record(self, phase: str, packet: dict, message_id: str) -> None:
        # Before sendall, or after the complete incoming frame has been parsed.
        observed_us = time.time_ns() // 1000
        record = {
            "schema": SCHEMA,
            "service": self.service,
            "process_id": os.getpid(),
            "phase": phase,
            "trace_id": packet["trace_id"],
            "message_id": message_id,
            "attempt": packet["attempt"],
            "ts_unix_us": str(observed_us),
        }
        self.file.write(json.dumps(record, separators=(",", ":")) + "\n")
        self.file.flush()


def serve(args) -> None:
    recorder = Recorder(args.raw, "B")
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen(1)
            listener.settimeout(10)
            with args.ready.open("x", encoding="utf-8") as ready:
                json.dump({"host": "127.0.0.1", "port": listener.getsockname()[1],
                           "process_id": os.getpid()}, ready)
            connection, _ = listener.accept()
            with connection:
                connection.settimeout(5)
                with connection.makefile("rb") as stream:
                    for _ in range(args.requests):
                        request = receive_packet(stream)
                        if (set(request) != {"kind", "trace_id", "request_id", "response_id", "attempt"}
                                or request["kind"] != "request" or type(request["attempt"]) is not int
                                or request["attempt"] != 0):
                            raise ValueError("unexpected request envelope")
                        for key in ("trace_id", "request_id", "response_id"):
                            if not isinstance(request[key], str) or not request[key]:
                                raise ValueError("missing RPC identity")
                        recorder.record("request_receive", request, request["request_id"])
                        time.sleep(args.processing_ms / 1000)
                        response = dict(request, kind="response")
                        recorder.record("response_send", response, response["response_id"])
                        send_packet(connection, response)
    finally:
        recorder.file.close()


def call(args) -> None:
    recorder = Recorder(args.raw, "A")
    try:
        with socket.create_connection(("127.0.0.1", args.port), timeout=5) as connection:
            with connection.makefile("rb") as stream:
                for index in range(args.requests):
                    request = {
                        "kind": "request",
                        "trace_id": f"{args.run_id}-{index + 1:04d}",
                        "request_id": f"request-{index + 1:04d}",
                        "response_id": f"response-{index + 1:04d}",
                        "attempt": 0,
                    }
                    recorder.record("request_send", request, request["request_id"])
                    send_packet(connection, request)
                    response = receive_packet(stream)
                    if response != dict(request, kind="response"):
                        raise ValueError("response does not match the transmitted message identities")
                    recorder.record("response_receive", response, response["response_id"])
    finally:
        recorder.file.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--role", choices=("A", "B"), required=True)
    parser.add_argument("--raw", type=Path, required=True)
    parser.add_argument("--requests", type=int, required=True)
    parser.add_argument("--processing-ms", type=int, default=10)
    parser.add_argument("--ready", type=Path)
    parser.add_argument("--port", type=int)
    parser.add_argument("--run-id", default="local")
    args = parser.parse_args()
    if not 1 <= args.requests <= 16 or not 0 <= args.processing_ms <= 200:
        parser.error("requests must be 1..16 and processing-ms must be 0..200")
    if args.role == "B":
        if args.ready is None:
            parser.error("B requires --ready")
        serve(args)
    else:
        if args.port is None or not 1 <= args.port <= 65535:
            parser.error("A requires a valid --port")
        call(args)


if __name__ == "__main__":
    main()
