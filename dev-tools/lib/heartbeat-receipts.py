#!/usr/bin/env python3
"""Strict, bounded, opt-in response-consumption snapshot for heartbeat writes.

Python 3 is required only when both interaction environment variables are set.
This records identities, not authorization or answer contents. Consumers must
match the run and every interaction/decision/context tuple independently, and
require the optional actionExecution pair when their execution state needs it.
"""
import json
import os
import re
import stat
import sys

UUID = re.compile(r"[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}")
DIGEST = re.compile(r"[a-f0-9]{64}")
IDENTITY_FIELDS = {"runId", "interactionId", "decisionId", "contextDigest"}


def validate_action_execution(value):
    if not isinstance(value, dict) or set(value) != {"claimVersion", "receiptDigest"}:
        raise ValueError("invalid action execution fields")
    version = value["claimVersion"]
    if type(version) is not int or not 1 <= version <= 2147483647:
        raise ValueError("invalid action claim version")
    digest = value["receiptDigest"]
    if not isinstance(digest, str) or not DIGEST.fullmatch(digest):
        raise ValueError("invalid action receipt digest")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate field")
        result[key] = value
    return result


def open_directory(path):
    if not path.startswith("/") or any(part in (".", "..") for part in path.split("/")):
        raise ValueError("absolute non-traversing receipt directory required")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    descriptor = os.open("/", flags)
    try:
        for part in filter(None, path.split("/")):
            child = os.open(part, flags, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def snapshot(path, run_id):
    if not UUID.fullmatch(run_id):
        raise ValueError("invalid interaction run")
    directory = open_directory(path)
    try:
        names = []
        with os.scandir(directory) as entries:
            for entry in entries:
                names.append(entry.name)
                if len(names) > 256:
                    raise ValueError("too many receipt entries")
        receipts = []
        for name in sorted(names):
            if name.endswith(".json.tmp") and UUID.fullmatch(name[:-9]):
                continue  # In-progress atomic publication is not consumption evidence.
            if not name.endswith(".json") or not UUID.fullmatch(name[:-5]):
                raise ValueError("invalid receipt filename")
            descriptor = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
            with os.fdopen(descriptor, "rb") as source:
                info = os.fstat(source.fileno())
                if not stat.S_ISREG(info.st_mode) or info.st_size > 4096:
                    raise ValueError("receipt is not a bounded regular file")
                raw = source.read(4097)
            if len(raw) > 4096:
                raise ValueError("receipt grew past limit")
            item = json.loads(raw, object_pairs_hook=unique_object)
            if not isinstance(item, dict) or set(item) not in (IDENTITY_FIELDS, IDENTITY_FIELDS | {"actionExecution"}):
                raise ValueError("invalid receipt fields")
            if not all(isinstance(item[key], str) for key in IDENTITY_FIELDS):
                raise ValueError("receipt fields must be strings")
            if item["runId"] != run_id or item["interactionId"] != name[:-5] or not UUID.fullmatch(item["decisionId"]) or not DIGEST.fullmatch(item["contextDigest"]):
                raise ValueError("receipt identity mismatch")
            if "actionExecution" in item:
                validate_action_execution(item["actionExecution"])
            receipts.append({key: value for key, value in item.items() if key != "runId"})
            if len(receipts) > 128:
                raise ValueError("too many consumed interactions")
        return receipts
    finally:
        os.close(directory)


if __name__ == "__main__":
    try:
        if len(sys.argv) != 3:
            raise ValueError("receipt directory and run required")
        print(json.dumps(snapshot(sys.argv[1], sys.argv[2]), separators=(",", ":")))
    except (ValueError, OSError) as error:
        print("heartbeat-receipts: invalid or unreadable consumption evidence", file=sys.stderr)
        sys.exit(2)
