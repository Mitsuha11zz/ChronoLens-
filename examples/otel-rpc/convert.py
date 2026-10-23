"""Convert OTLP JSON RPC spans to ChronoLens message-start events."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import re
import sys


MAX_INPUT_BYTES = 8 * 1024 * 1024
MAX_EVENTS = 10_000
MAX_CLOCK_DOMAINS = 64
MAX_FIELD_BYTES = 4 * 1024
MAX_UINT64 = (1 << 64) - 1

SPAN_KIND_SERVER = 2
SPAN_KIND_CLIENT = 3


class ConversionError(ValueError):
    pass


@dataclass(frozen=True)
class RpcSpan:
    trace_id: str
    span_id: str
    parent_span_id: str | None
    kind: int
    timestamp_us: int
    clock_id: str


@dataclass(frozen=True)
class ConversionStats:
    client_spans: int
    server_spans: int
    matched_parent_links: int
    clients_without_server: int
    servers_without_client: int
    clients_with_multiple_servers: int
    ignored_spans: int
    clock_domains: int


def reject_constant(value: str) -> None:
    raise ConversionError(f"invalid JSON numeric constant: {value}")


def unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ConversionError(f"duplicate JSON object key: {key}")
        result[key] = value
    return result


def require_object(value: object, where: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise ConversionError(f"{where} must be a JSON object")
    return value


def repeated_field(owner: dict[str, object], name: str, where: str) -> list[object]:
    value = owner.get(name, [])
    if not isinstance(value, list):
        raise ConversionError(f"{where}.{name} must be an array")
    return value


def resource_attributes(resource: object, where: str) -> dict[str, object]:
    if resource is None:
        return {}
    resource_obj = require_object(resource, where)
    result: dict[str, object] = {}
    for index, raw_attribute in enumerate(repeated_field(resource_obj, "attributes", where)):
        attribute = require_object(raw_attribute, f"{where}.attributes[{index}]")
        key = attribute.get("key")
        if not isinstance(key, str) or not key.strip():
            raise ConversionError(f"{where}.attributes[{index}].key must be a non-empty string")
        if key in result:
            raise ConversionError(f"{where} has duplicate resource attribute {key!r}")
        result[key] = attribute.get("value")
    return result


def string_attribute(attributes: dict[str, object], key: str, where: str) -> str | None:
    raw_value = attributes.get(key)
    if raw_value is None:
        return None
    value_obj = require_object(raw_value, f"{where}.{key}")
    value = value_obj.get("stringValue")
    if not isinstance(value, str) or not value.strip():
        raise ConversionError(f"{where}.{key} must use a non-empty stringValue")
    if len(value.encode("utf-8")) > MAX_FIELD_BYTES:
        raise ConversionError(f"{where}.{key} exceeds the {MAX_FIELD_BYTES}-byte field limit")
    return value


def service_namespace(attributes: dict[str, object], where: str) -> str | None:
    raw_value = attributes.get("service.namespace")
    if raw_value is None:
        return None
    value_obj = require_object(raw_value, f"{where}.service.namespace")
    value = value_obj.get("stringValue")
    if not isinstance(value, str):
        raise ConversionError(f"{where}.service.namespace must use a stringValue")
    if value == "":
        return None
    if not value.strip():
        raise ConversionError(f"{where}.service.namespace cannot contain only whitespace")
    if len(value.encode("utf-8")) > MAX_FIELD_BYTES:
        raise ConversionError(f"{where}.service.namespace exceeds the {MAX_FIELD_BYTES}-byte field limit")
    return value


def clock_id_for(
    attributes: dict[str, object], attribute_name: str, where: str
) -> str:
    value = string_attribute(attributes, attribute_name, where)
    if value is None:
        raise ConversionError(
            f"{where} is missing resource attribute {attribute_name!r}; "
            "choose a resource attribute that identifies the intended clock domain"
        )

    if attribute_name == "service.instance.id":
        service_name = string_attribute(attributes, "service.name", where)
        if service_name is None:
            raise ConversionError(
                f"{where} needs service.name when using service.instance.id as the clock key"
            )
        namespace = service_namespace(attributes, where)
        service = f"{namespace}/{service_name}" if namespace is not None else service_name
        clock_id = f"{service}@{value}"
    else:
        # A host or custom attribute can intentionally group several services
        # under one shared clock domain.
        clock_id = value

    if len(clock_id.encode("utf-8")) > MAX_FIELD_BYTES:
        raise ConversionError(f"{where} produces a clock_id over the {MAX_FIELD_BYTES}-byte limit")
    return clock_id


def hex_identifier(value: object, digits: int, where: str, *, optional: bool = False) -> str | None:
    if optional and (value is None or value == ""):
        return None
    if not isinstance(value, str) or re.fullmatch(rf"[0-9a-fA-F]{{{digits}}}", value) is None:
        raise ConversionError(f"{where} must contain exactly {digits} hexadecimal characters")
    normalized = value.lower()
    if int(normalized, 16) == 0:
        raise ConversionError(f"{where} cannot be all zeroes")
    return normalized


def uint64_json(value: object, where: str) -> int:
    if type(value) is int:
        result = value
    elif isinstance(value, str) and re.fullmatch(r"(?:0|[1-9][0-9]*)", value):
        result = int(value)
    else:
        raise ConversionError(f"{where} must be a non-negative exact integer or decimal string")
    if not 0 <= result <= MAX_UINT64:
        raise ConversionError(f"{where} is outside the uint64 range")
    return result


def read_rpc_spans(
    document: dict[str, object], clock_attribute: str
) -> tuple[list[RpcSpan], int]:
    raw_resources = document.get("resourceSpans")
    if not isinstance(raw_resources, list):
        raise ConversionError("OTLP JSON must contain a resourceSpans array")

    spans: list[RpcSpan] = []
    identities: set[tuple[str, str]] = set()
    ignored_spans = 0

    for resource_index, raw_resource_spans in enumerate(raw_resources):
        resource_where = f"resourceSpans[{resource_index}].resource"
        resource_spans = require_object(raw_resource_spans, f"resourceSpans[{resource_index}]")
        attributes = resource_attributes(resource_spans.get("resource"), resource_where)
        scope_where = f"resourceSpans[{resource_index}].scopeSpans"

        for scope_index, raw_scope in enumerate(repeated_field(resource_spans, "scopeSpans", f"resourceSpans[{resource_index}]")):
            scope_where_indexed = f"{scope_where}[{scope_index}]"
            scope = require_object(raw_scope, scope_where_indexed)
            for span_index, raw_span in enumerate(repeated_field(scope, "spans", scope_where_indexed)):
                where = f"{scope_where_indexed}.spans[{span_index}]"
                span = require_object(raw_span, where)
                kind = span.get("kind", 0)
                if type(kind) is not int:
                    raise ConversionError(f"{where}.kind must be an OTLP numeric enum value")
                if kind not in (SPAN_KIND_CLIENT, SPAN_KIND_SERVER):
                    ignored_spans += 1
                    continue

                trace_id = hex_identifier(span.get("traceId"), 32, f"{where}.traceId")
                span_id = hex_identifier(span.get("spanId"), 16, f"{where}.spanId")
                parent_span_id = hex_identifier(
                    span.get("parentSpanId"), 16, f"{where}.parentSpanId", optional=True
                )
                timestamp_ns = uint64_json(span.get("startTimeUnixNano"), f"{where}.startTimeUnixNano")
                clock_id = clock_id_for(attributes, clock_attribute, resource_where)
                identity = (trace_id, span_id)
                if identity in identities:
                    raise ConversionError(
                        f"duplicate span identity in trace {trace_id}: {span_id}"
                    )
                identities.add(identity)
                spans.append(
                    RpcSpan(
                        trace_id=trace_id,
                        span_id=span_id,
                        parent_span_id=parent_span_id,
                        kind=kind,
                        timestamp_us=timestamp_ns // 1_000,
                        clock_id=clock_id,
                    )
                )
                if len(spans) > MAX_EVENTS:
                    raise ConversionError(f"RPC span count exceeds the {MAX_EVENTS}-event limit")

    return spans, ignored_spans


def convert_document(
    document: object, clock_attribute: str
) -> tuple[list[dict[str, object]], ConversionStats]:
    root = require_object(document, "OTLP JSON root")
    spans, ignored_spans = read_rpc_spans(root, clock_attribute)
    if not spans:
        raise ConversionError("no CLIENT or SERVER RPC spans were found")

    clients = {
        (span.trace_id, span.span_id): span
        for span in spans
        if span.kind == SPAN_KIND_CLIENT
    }
    servers = [span for span in spans if span.kind == SPAN_KIND_SERVER]
    client_children: dict[tuple[str, str], int] = {key: 0 for key in clients}
    server_parent_keys: list[tuple[str, str] | None] = []

    for server in servers:
        parent_key = (
            (server.trace_id, server.parent_span_id)
            if server.parent_span_id is not None
            else None
        )
        if parent_key is not None and parent_key in clients:
            client_children[parent_key] += 1
            server_parent_keys.append(parent_key)
        else:
            server_parent_keys.append(None)

    events: list[dict[str, object]] = []
    for span in spans:
        if span.kind == SPAN_KIND_CLIENT:
            message_id = f"otel-rpc:{span.span_id}:request"
            event_kind = "send"
        else:
            parent = span.parent_span_id or f"orphan-{span.span_id}"
            message_id = f"otel-rpc:{parent}:request"
            event_kind = "receive"

        events.append(
            {
                "event_id": f"otel:{span.trace_id}:{span.span_id}:start",
                "clock_id": span.clock_id,
                "trace_id": span.trace_id,
                "message_id": message_id,
                "attempt": 0,
                "kind": event_kind,
                "ts_us": str(span.timestamp_us),
            }
        )

    if len({span.clock_id for span in spans}) > MAX_CLOCK_DOMAINS:
        raise ConversionError(
            f"clock domain count exceeds ChronoLens' {MAX_CLOCK_DOMAINS}-domain default limit"
        )

    stats = ConversionStats(
        client_spans=len(clients),
        server_spans=len(servers),
        matched_parent_links=sum(parent is not None for parent in server_parent_keys),
        clients_without_server=sum(count == 0 for count in client_children.values()),
        servers_without_client=sum(parent is None for parent in server_parent_keys),
        clients_with_multiple_servers=sum(count > 1 for count in client_children.values()),
        ignored_spans=ignored_spans,
        clock_domains=len({span.clock_id for span in spans}),
    )
    return events, stats


def read_document(path: Path) -> object:
    try:
        size = path.stat().st_size
    except OSError as error:
        raise ConversionError(f"cannot stat input {path.name!r}: {error}") from error
    if size > MAX_INPUT_BYTES:
        raise ConversionError(f"input exceeds the {MAX_INPUT_BYTES}-byte limit")
    try:
        payload = path.read_bytes()
        if len(payload) > MAX_INPUT_BYTES:
            raise ConversionError(f"input exceeds the {MAX_INPUT_BYTES}-byte limit")
        text = payload.decode("utf-8")
        return json.loads(
            text,
            object_pairs_hook=unique_object,
            parse_constant=reject_constant,
        )
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ConversionError(f"cannot read OTLP JSON from {path.name!r}: {error}") from error


def jsonl_bytes(events: list[dict[str, object]]) -> bytes:
    text = "".join(
        json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n"
        for event in events
    )
    payload = text.encode("utf-8")
    if len(payload) > MAX_INPUT_BYTES:
        raise ConversionError(
            f"converted JSONL exceeds ChronoLens' {MAX_INPUT_BYTES}-byte default input limit"
        )
    return payload


def write_output(path: Path, payload: bytes, *, force: bool) -> None:
    try:
        with path.open("wb" if force else "xb") as output:
            output.write(payload)
    except FileExistsError as error:
        raise ConversionError(
            f"output already exists: {path.name!r}; pass --force to overwrite"
        ) from error
    except OSError as error:
        raise ConversionError(f"cannot write output {path.name!r}: {error}") from error


def print_summary(stats: ConversionStats, event_count: int) -> None:
    print(
        f"Converted {event_count} RPC span-start events across {stats.clock_domains} clock domains.",
        file=sys.stderr,
    )
    print(
        "RPC parent links: "
        f"{stats.matched_parent_links}; clients without an exported server: "
        f"{stats.clients_without_server}; servers without an exported client: "
        f"{stats.servers_without_client}; clients with multiple server spans: "
        f"{stats.clients_with_multiple_servers}; ignored non-RPC spans: {stats.ignored_spans}.",
        file=sys.stderr,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="OTLP JSON ExportTraceServiceRequest")
    parser.add_argument("--output", type=Path, help="ChronoLens JSONL path; default: stdout")
    parser.add_argument(
        "--clock-attribute",
        default="service.instance.id",
        help=(
            "resource attribute used as a clock domain (default: service.instance.id); "
            "host.name can group services on the same host"
        ),
    )
    parser.add_argument("--force", action="store_true", help="overwrite an existing output file")
    args = parser.parse_args()

    if not args.clock_attribute.strip() or len(args.clock_attribute.encode("utf-8")) > 255:
        parser.error("--clock-attribute must be a non-empty name up to 255 UTF-8 bytes")

    try:
        if args.output is not None and args.input.resolve() == args.output.resolve():
            raise ConversionError("input and output paths must be different")
        document = read_document(args.input)
        events, stats = convert_document(document, args.clock_attribute)
        payload = jsonl_bytes(events)
        if args.output is None:
            sys.stdout.buffer.write(payload)
        else:
            write_output(args.output, payload, force=args.force)
        print_summary(stats, len(events))
    except (ConversionError, OSError, ValueError) as error:
        print(f"chronolens-otel: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
