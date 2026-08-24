#!/usr/bin/env python3
"""Pinned test-only Ed25519 fixture helper; production verification stays OpenSSL."""

from __future__ import annotations

import argparse
import base64
import binascii
import json
import re
import secrets
import sys

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat


DIGEST_RE = re.compile(r"sha256:([0-9a-f]{64})")


class InputError(ValueError):
    pass


def decode_b64(value: str, length: int, label: str) -> bytes:
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, binascii.Error) as error:
        raise InputError(f"invalid {label}") from error
    if len(decoded) != length:
        raise InputError(f"invalid {label}")
    return decoded


def decode_digest(value: str) -> bytes:
    match = DIGEST_RE.fullmatch(value)
    if not match:
        raise InputError("invalid digest")
    return bytes.fromhex(match.group(1))


def decode_private_key(value: str) -> bytes:
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, binascii.Error) as error:
        raise InputError("invalid private key") from error
    # Test fixtures historically used libsodium's seed||public-key secret wire
    # shape. Authenticate its suffix before passing the seed to cryptography.
    if len(decoded) == 64:
        seed, supplied_public = decoded[:32], decoded[32:]
        derived_public = Ed25519PrivateKey.from_private_bytes(seed).public_key().public_bytes(
            Encoding.Raw, PublicFormat.Raw
        )
        if supplied_public != derived_public:
            raise InputError("invalid private key")
        decoded = seed
    if len(decoded) != 32:
        raise InputError("invalid private key")
    return decoded


def read_lines(count: int) -> list[str]:
    lines = sys.stdin.read().splitlines()
    if len(lines) != count:
        raise InputError("invalid input line count")
    return lines


def emit_keypair(seed: bytes) -> None:
    private_key = Ed25519PrivateKey.from_private_bytes(seed)
    public_key = private_key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
    print(base64.b64encode(public_key).decode("ascii"))
    print(base64.b64encode(seed).decode("ascii"))


def verify_record(record: object, index: int | None = None) -> None:
    suffix = "" if index is None else f":{index}"
    if not isinstance(record, dict):
        raise InputError(f"SIGNATURE_WIRE_LENGTH{suffix}")
    message = record.get("message")
    signature = record.get("signature")
    public_key = record.get("public_key")
    if not isinstance(message, str) or not isinstance(signature, str) or not isinstance(public_key, str):
        raise InputError(f"SIGNATURE_WIRE_LENGTH{suffix}")
    if not message.startswith("sha256:") or not signature.startswith("ed25519:"):
        raise InputError(f"SIGNATURE_FRAMING{suffix}")
    try:
        Ed25519PublicKey.from_public_bytes(decode_b64(public_key, 32, "public key")).verify(
            decode_b64(signature[8:], 64, "signature"), decode_digest(message)
        )
    except InvalidSignature as error:
        raise InputError(f"SIGNATURE_INVALID{suffix}") from error


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "command",
        choices=("seed", "keypair", "keypair-from-seed", "sign", "verify", "verify-json"),
    )
    args = parser.parse_args()
    try:
        if args.command == "seed":
            print(secrets.token_hex(32))
        elif args.command == "keypair":
            emit_keypair(secrets.token_bytes(32))
        elif args.command == "keypair-from-seed":
            value = sys.stdin.read().strip()
            if not re.fullmatch(r"[0-9a-f]{64}", value):
                raise InputError("invalid seed")
            emit_keypair(bytes.fromhex(value))
        elif args.command == "sign":
            private_text, digest_text = read_lines(2)
            private_key = Ed25519PrivateKey.from_private_bytes(decode_private_key(private_text))
            signature = private_key.sign(decode_digest(digest_text))
            print("ed25519:" + base64.b64encode(signature).decode("ascii"))
        elif args.command == "verify":
            public_text, digest_text, signature_text = read_lines(3)
            verify_record(
                {"public_key": public_text, "message": digest_text, "signature": signature_text}
            )
            print("VERIFIED")
        else:
            records = json.load(sys.stdin)
            if isinstance(records, list):
                for index, record in enumerate(records):
                    verify_record(record, index)
            else:
                verify_record(records)
            print("VERIFIED")
    except (InputError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
