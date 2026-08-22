#!/usr/bin/env python3
"""Pinned zero-to-one wire validator for the customer-delivery bootstrap.

This trust-computing-base executable intentionally has no import-time side
effects.  It accepts only canonical JSON, resolves only closed JSON pointers,
and exposes validation/canonicalization before the later signed provider
registration enables stateful genesis operations.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from hashlib import sha256
from pathlib import Path
from typing import Any, NoReturn


MAX_INT64 = (1 << 63) - 1
MIN_INT64 = -(1 << 63)
WIRE_FRAGMENT_COUNT = 44


class BootstrapError(ValueError):
    """A closed-contract validation or execution failure."""


def fail(message: str) -> NoReturn:
    raise BootstrapError(message)


def reject_float(value: str) -> NoReturn:
    fail(f"floating-point value is forbidden: {value}")


def reject_constant(value: str) -> NoReturn:
    fail(f"non-finite value is forbidden: {value}")


def closed_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            fail(f"duplicate key: {key}")
        result[key] = value
    return result


def validate_json_value(value: Any, pointer: str = "$") -> None:
    if value is None or isinstance(value, (str, bool)):
        if isinstance(value, str):
            for char in value:
                codepoint = ord(char)
                if codepoint == 0:
                    fail(f"U+0000 is forbidden at {pointer}")
                if 0xD800 <= codepoint <= 0xDFFF:
                    fail(f"unpaired surrogate is forbidden at {pointer}")
        return
    if isinstance(value, int):
        if value < MIN_INT64 or value > MAX_INT64:
            fail(f"integer is outside signed 64-bit range at {pointer}")
        return
    if isinstance(value, float):
        fail(f"floating-point value is forbidden at {pointer}")
    if isinstance(value, list):
        for index, item in enumerate(value):
            validate_json_value(item, f"{pointer}/{index}")
        return
    if isinstance(value, dict):
        for key, item in value.items():
            validate_json_value(key, f"{pointer}/<key>")
            validate_json_value(item, f"{pointer}/{escape_pointer(key)}")
        return
    fail(f"unsupported JSON value at {pointer}: {type(value).__name__}")


def load_json_bytes(raw: bytes) -> Any:
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as error:
        fail(f"invalid UTF-8: {error}")
    if text.startswith("\ufeff"):
        fail("UTF-8 BOM is forbidden")
    try:
        value = json.loads(
            text,
            object_pairs_hook=closed_object,
            parse_float=reject_float,
            parse_constant=reject_constant,
        )
    except json.JSONDecodeError as error:
        fail(f"invalid JSON: {error.msg} at line {error.lineno} column {error.colno}")
    validate_json_value(value)
    return value


def load_json(path: Path) -> Any:
    try:
        return load_json_bytes(path.read_bytes())
    except OSError as error:
        fail(f"cannot read {path}: {error}")


def canonical_bytes(value: Any) -> bytes:
    validate_json_value(value)
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def canonical_file_bytes(value: Any) -> bytes:
    return canonical_bytes(value) + b"\n"


def digest_bytes(raw: bytes) -> str:
    return sha256(raw).hexdigest()


def escape_pointer(component: str) -> str:
    return component.replace("~", "~0").replace("/", "~1")


def resolve_pointer(document: Any, pointer: str) -> Any:
    if pointer in ("", "#"):
        return document
    if pointer.startswith("#"):
        pointer = pointer[1:]
    if not pointer.startswith("/"):
        fail(f"invalid JSON Pointer: {pointer}")
    current = document
    for encoded in pointer[1:].split("/"):
        token = encoded.replace("~1", "/").replace("~0", "~")
        if isinstance(current, dict):
            if token not in current:
                fail(f"dangling JSON Pointer: {pointer}")
            current = current[token]
        elif isinstance(current, list):
            if not token.isascii() or not token.isdigit() or (token != "0" and token.startswith("0")):
                fail(f"invalid array index in JSON Pointer: {pointer}")
            index = int(token)
            if index >= len(current):
                fail(f"array index outside JSON Pointer target: {pointer}")
            current = current[index]
        else:
            fail(f"JSON Pointer traverses a scalar: {pointer}")
    return current


def is_type(value: Any, expected: str) -> bool:
    if expected == "null":
        return value is None
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return (isinstance(value, (int, float)) and not isinstance(value, bool))
    if expected == "string":
        return isinstance(value, str)
    if expected == "array":
        return isinstance(value, list)
    if expected == "object":
        return isinstance(value, dict)
    return False


def validate_schema(value: Any, schema: dict[str, Any], root: dict[str, Any], pointer: str = "$") -> None:
    if "$ref" in schema:
        ref = schema["$ref"]
        if not isinstance(ref, str) or not ref.startswith("#"):
            fail(f"external schema reference is forbidden at {pointer}")
        validate_schema(value, resolve_pointer(root, ref), root, pointer)
        return

    if "const" in schema and value != schema["const"]:
        fail(f"expected constant {schema['const']!r} at {pointer}")
    if "enum" in schema and value not in schema["enum"]:
        fail(f"value is outside the enum at {pointer}")
    if "anyOf" in schema:
        errors: list[str] = []
        for candidate in schema["anyOf"]:
            try:
                validate_schema(value, candidate, root, pointer)
                break
            except BootstrapError as error:
                errors.append(str(error))
        else:
            fail(f"no anyOf branch matched at {pointer}: {'; '.join(errors)}")
        return
    if "oneOf" in schema:
        matches = 0
        for candidate in schema["oneOf"]:
            try:
                validate_schema(value, candidate, root, pointer)
                matches += 1
            except BootstrapError:
                pass
        if matches != 1:
            fail(f"expected exactly one matching schema at {pointer}, got {matches}")
        return

    declared_type = schema.get("type")
    if isinstance(declared_type, str):
        if not is_type(value, declared_type):
            fail(f"expected {declared_type} at {pointer}")
    elif isinstance(declared_type, list):
        if not all(isinstance(item, str) for item in declared_type):
            fail(f"invalid type declaration at {pointer}")
        if not any(is_type(value, item) for item in declared_type):
            fail(f"value has no allowed type at {pointer}")
    elif declared_type is not None:
        fail(f"invalid type declaration at {pointer}")

    if isinstance(value, dict):
        properties = schema.get("properties", {})
        required = schema.get("required", [])
        if not isinstance(properties, dict) or not isinstance(required, list):
            fail(f"invalid object schema at {pointer}")
        for key in required:
            if key not in value:
                fail(f"missing required field: {key} at {pointer}")
        unknown = sorted(set(value) - set(properties))
        if unknown and schema.get("additionalProperties") is False:
            fail(f"unknown field: {unknown[0]} at {pointer}")
        for key, item in value.items():
            if key in properties:
                validate_schema(item, properties[key], root, f"{pointer}/{escape_pointer(key)}")
    elif isinstance(value, list):
        minimum = schema.get("minItems")
        maximum = schema.get("maxItems")
        if minimum is not None and len(value) < minimum:
            fail(f"array has fewer than {minimum} items at {pointer}")
        if maximum is not None and len(value) > maximum:
            fail(f"array has more than {maximum} items at {pointer}")
        if schema.get("uniqueItems"):
            encoded = [canonical_bytes(item) for item in value]
            if len(set(encoded)) != len(encoded):
                fail(f"array contains duplicate items at {pointer}")
        item_schema = schema.get("items")
        if isinstance(item_schema, dict):
            for index, item in enumerate(value):
                validate_schema(item, item_schema, root, f"{pointer}/{index}")
    elif isinstance(value, str):
        length = len(value)
        if "minLength" in schema and length < schema["minLength"]:
            fail(f"string is too short at {pointer}")
        if "maxLength" in schema and length > schema["maxLength"]:
            fail(f"string is too long at {pointer}")
        pattern = schema.get("pattern")
        if pattern is not None and re.fullmatch(pattern, value) is None:
            fail(f"string does not match required pattern at {pointer}")
    elif isinstance(value, int) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            fail(f"integer is below minimum at {pointer}")
        if "maximum" in schema and value > schema["maximum"]:
            fail(f"integer is above maximum at {pointer}")


def self_test_schema(schema: dict[str, Any]) -> None:
    if set(schema) != {"$defs", "$id", "$schema"}:
        fail("wire schema top level is not closed")
    definitions = schema.get("$defs")
    if not isinstance(definitions, dict) or len(definitions) != WIRE_FRAGMENT_COUNT:
        fail(f"wire schema must contain exactly {WIRE_FRAGMENT_COUNT} fragments")

    def walk(node: Any, pointer: str) -> None:
        if isinstance(node, dict):
            if node.get("type") == "object":
                if node.get("additionalProperties") is not False:
                    fail(f"open object schema at {pointer}")
                properties = node.get("properties")
                required = node.get("required")
                if not isinstance(properties, dict) or not isinstance(required, list):
                    fail(f"incomplete object schema at {pointer}")
                if set(properties) != set(required) or len(required) != len(set(required)):
                    fail(f"object fields are not exactly required at {pointer}")
            for key, item in node.items():
                walk(item, f"{pointer}/{escape_pointer(key)}")
        elif isinstance(node, list):
            for index, item in enumerate(node):
                walk(item, f"{pointer}/{index}")

    walk(schema, "#")


def confined_path(root: Path, relative: str, *, must_exist: bool = True) -> Path:
    if not relative or "\x00" in relative:
        fail("empty or NUL path is forbidden")
    candidate_path = Path(relative)
    if candidate_path.is_absolute() or any(part in ("", ".", "..") for part in candidate_path.parts):
        fail(f"path is not a normalized relative path: {relative}")
    root_real = root.resolve(strict=True)
    candidate = root_real.joinpath(candidate_path)
    parent_real = candidate.parent.resolve(strict=True)
    try:
        parent_real.relative_to(root_real)
    except ValueError:
        fail(f"path escapes root: {relative}")
    if must_exist:
        resolved = candidate.resolve(strict=True)
        try:
            resolved.relative_to(root_real)
        except ValueError:
            fail(f"resolved path escapes root: {relative}")
        if candidate.is_symlink():
            fail(f"symlink target is forbidden: {relative}")
        return resolved
    if candidate.exists() and candidate.is_symlink():
        fail(f"symlink target is forbidden: {relative}")
    return candidate


def atomic_write(path: Path, raw: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "wb", closefd=True) as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory_fd = os.open(path.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except BaseException:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
        raise


@dataclass(frozen=True)
class ProcessEvidence:
    argv: tuple[str, ...]
    deadline_minutes: int
    result_exit_code: int
    raw_wait_status: int | None
    timed_out: bool
    termination_signal: int | None
    forced_kill: bool
    descendants_survived: bool
    stdout: bytes
    stderr: bytes


def run_bounded(argv: list[str], deadline_minutes: int, *, cwd: Path, env: dict[str, str]) -> ProcessEvidence:
    if not isinstance(deadline_minutes, int) or isinstance(deadline_minutes, bool) or not 1 <= deadline_minutes <= 60:
        fail("deadline_minutes must be an integer from 1 through 60")
    if not argv or any(not isinstance(item, str) or "\x00" in item for item in argv):
        fail("argv must contain non-NUL strings")
    process = subprocess.Popen(
        argv,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
        shell=False,
    )
    timed_out = False
    forced_kill = False
    raw_status: int | None = None
    try:
        stdout, stderr = process.communicate(timeout=deadline_minutes * 60)
    except subprocess.TimeoutExpired:
        timed_out = True
        os.killpg(process.pid, signal.SIGTERM)
        try:
            stdout, stderr = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            forced_kill = True
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
    return_code = process.returncode
    if timed_out:
        normalized = 143
        termination_signal = signal.SIGTERM
        if return_code is not None and return_code < 0:
            raw_status = -return_code
    else:
        normalized = return_code if return_code is not None and return_code >= 0 else 128 + abs(return_code or 0)
        termination_signal = -return_code if return_code is not None and return_code < 0 else None
        if return_code is not None and return_code < 0:
            raw_status = -return_code
    descendants_survived = False
    try:
        os.killpg(process.pid, 0)
    except ProcessLookupError:
        pass
    except PermissionError:
        descendants_survived = True
    else:
        descendants_survived = True
    return ProcessEvidence(
        argv=tuple(argv),
        deadline_minutes=deadline_minutes,
        result_exit_code=normalized,
        raw_wait_status=raw_status,
        timed_out=timed_out,
        termination_signal=termination_signal,
        forced_kill=forced_kill,
        descendants_survived=descendants_survived,
        stdout=stdout,
        stderr=stderr,
    )


def parse_arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wire-schema", required=True, type=Path)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--self-test-schema", action="store_true")
    mode.add_argument("--canonicalize-only", type=Path)
    mode.add_argument("--validate-only", type=Path)
    parser.add_argument("--schema-pointer")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_arguments(argv)
    schema_raw = args.wire_schema.read_bytes()
    schema = load_json_bytes(schema_raw)
    if canonical_file_bytes(schema) != schema_raw:
        fail("wire schema is not canonical JSON plus one LF")
    self_test_schema(schema)
    if args.self_test_schema:
        print(f"BOOTSTRAP_WIRE_SCHEMA_OK fragments={len(schema['$defs'])}")
        return 0
    if args.canonicalize_only is not None:
        value = load_json(args.canonicalize_only)
        sys.stdout.buffer.write(canonical_bytes(value) + b"\n")
        return 0
    if args.validate_only is not None:
        if not args.schema_pointer:
            fail("--schema-pointer is required with --validate-only")
        value = load_json(args.validate_only)
        fragment = resolve_pointer(schema, args.schema_pointer)
        if not isinstance(fragment, dict):
            fail("schema pointer does not resolve to an object")
        validate_schema(value, fragment, schema)
        print("BOOTSTRAP_WIRE_VALUE_OK")
        return 0
    fail("no execution mode selected")


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except BootstrapError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2)
