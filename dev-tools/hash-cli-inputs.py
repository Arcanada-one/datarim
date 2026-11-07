#!/usr/bin/env python3
"""Emit a bounded SHA-256 inventory of explicitly selected files."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
import sys


SCHEMA = "DatarimCliInputManifest/v1"
MAX_FILES = 64
MAX_FILE_BYTES = 1024 * 1024
MAX_TOTAL_BYTES = 16 * 1024 * 1024
CHUNK_BYTES = 64 * 1024


class InputRefused(Exception):
    """A handled input or filesystem refusal with no user-derived message."""


def _stable_stat(st: os.stat_result) -> tuple[int, int, int, int, int, int]:
    return (
        st.st_dev,
        st.st_ino,
        st.st_mode,
        st.st_size,
        st.st_mtime_ns,
        st.st_ctime_ns,
    )


def _directory_flags() -> int:
    required = ("O_NOFOLLOW", "O_DIRECTORY", "O_NONBLOCK")
    if os.name != "posix" or any(not hasattr(os, name) for name in required):
        raise InputRefused
    if os.open not in os.supports_dir_fd or os.stat not in os.supports_dir_fd:
        raise InputRefused
    if os.stat not in os.supports_follow_symlinks:
        raise InputRefused
    return os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)


def _open_root(path: str, flags: int) -> int:
    try:
        path.encode("utf-8", "strict")
    except UnicodeEncodeError as exc:
        raise InputRefused from exc
    if not path:
        raise InputRefused

    absolute = path.startswith("/")
    fd = os.open("/" if absolute else ".", flags)
    try:
        for component in path.split("/"):
            if component in ("", "."):
                continue
            next_fd = os.open(component, flags, dir_fd=fd)
            os.close(fd)
            fd = next_fd
        if not stat.S_ISDIR(os.fstat(fd).st_mode):
            raise InputRefused
        return fd
    except Exception:
        os.close(fd)
        raise


def _file_components(path: str) -> tuple[str, ...]:
    try:
        path.encode("utf-8", "strict")
    except UnicodeEncodeError as exc:
        raise InputRefused from exc
    if not path or path.startswith("/"):
        raise InputRefused
    components = tuple(path.split("/"))
    if any(component in ("", ".", "..") for component in components):
        raise InputRefused
    return components


def _open_selected(root_fd: int, components: tuple[str, ...], dir_flags: int):
    directory_fd = os.dup(root_fd)
    directory_stats = [_stable_stat(os.fstat(directory_fd))]
    try:
        for component in components[:-1]:
            next_fd = os.open(component, dir_flags, dir_fd=directory_fd)
            os.close(directory_fd)
            directory_fd = next_fd
            directory_stats.append(_stable_stat(os.fstat(directory_fd)))

        final_name = components[-1]
        link_stat = os.stat(final_name, dir_fd=directory_fd, follow_symlinks=False)
        if not stat.S_ISREG(link_stat.st_mode):
            raise InputRefused

        file_flags = (
            os.O_RDONLY
            | os.O_NOFOLLOW
            | os.O_NONBLOCK
            | getattr(os, "O_CLOEXEC", 0)
        )
        file_fd = os.open(final_name, file_flags, dir_fd=directory_fd)
        try:
            file_stat = os.fstat(file_fd)
            if not stat.S_ISREG(file_stat.st_mode):
                raise InputRefused
            if (link_stat.st_dev, link_stat.st_ino) != (file_stat.st_dev, file_stat.st_ino):
                raise InputRefused
            return file_fd, directory_stats, _stable_stat(file_stat)
        except Exception:
            os.close(file_fd)
            raise
    finally:
        os.close(directory_fd)


def _hash_one(
    root_fd: int,
    components: tuple[str, ...],
    total_so_far: int,
    dir_flags: int,
) -> tuple[dict[str, object], list[tuple[int, int, int, int, int, int]], tuple[int, int, int, int, int, int]]:
    fd, directory_stats, before = _open_selected(root_fd, components, dir_flags)
    try:
        if before[3] > MAX_FILE_BYTES:
            raise InputRefused
        digest = hashlib.sha256()
        byte_count = 0
        while True:
            remaining = min(MAX_FILE_BYTES - byte_count, MAX_TOTAL_BYTES - total_so_far - byte_count)
            chunk = os.read(fd, min(CHUNK_BYTES, remaining + 1))
            if not chunk:
                break
            if len(chunk) > remaining:
                raise InputRefused
            byte_count += len(chunk)
            digest.update(chunk)

        after = _stable_stat(os.fstat(fd))
        if before != after or byte_count != before[3]:
            raise InputRefused
        entry = {
            "relative_path": "/".join(components),
            "sha256": digest.hexdigest(),
            "byte_count": byte_count,
        }
        return entry, directory_stats, after
    finally:
        os.close(fd)


def _verify_unchanged(
    root_path: str,
    initial_root_stat: tuple[int, int, int, int, int, int],
    selection: list[tuple[tuple[str, ...], list[tuple[int, int, int, int, int, int]], tuple[int, int, int, int, int, int]]],
    dir_flags: int,
) -> None:
    fresh_root_fd = _open_root(root_path, dir_flags)
    try:
        if _stable_stat(os.fstat(fresh_root_fd)) != initial_root_stat:
            raise InputRefused
        for components, before_dirs, before_file in selection:
            file_fd, after_dirs, after_file = _open_selected(fresh_root_fd, components, dir_flags)
            os.close(file_fd)
            if before_dirs != after_dirs or before_file != after_file:
                raise InputRefused
    finally:
        os.close(fresh_root_fd)


def _summary(result: str, exit_code: int, codes: list[str], count: int | None, status: str, files: list[dict[str, object]]) -> dict[str, object]:
    return {
        "schema": SCHEMA,
        "result": result,
        "exit_code": exit_code,
        "diagnostic_codes": codes,
        "file_count": count,
        "file_count_status": status,
        "files": files,
    }


def _write_summary(value: dict[str, object]) -> None:
    sys.stdout.write(json.dumps(value, ensure_ascii=True, separators=(",", ":")) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, help="explicit directory root for selected paths")
    parser.add_argument("--file", action="append", required=True, help="canonical relative POSIX path; repeatable")
    args = parser.parse_args()

    try:
        if len(args.file) > MAX_FILES:
            raise InputRefused
        selected = [(_file_components(path), path) for path in args.file]
        names = [path for _, path in selected]
        if len(set(names)) != len(names):
            raise InputRefused
        selected.sort(key=lambda pair: pair[1])

        dir_flags = _directory_flags()
        root_fd = _open_root(args.root, dir_flags)
        try:
            initial_root_stat = _stable_stat(os.fstat(root_fd))
            total = 0
            output: list[dict[str, object]] = []
            selection_state = []
            for components, _ in selected:
                entry, directories, file_stat = _hash_one(root_fd, components, total, dir_flags)
                total += int(entry["byte_count"])
                if total > MAX_TOTAL_BYTES:
                    raise InputRefused
                output.append(entry)
                selection_state.append((components, directories, file_stat))
            _verify_unchanged(args.root, initial_root_stat, selection_state, dir_flags)
        finally:
            os.close(root_fd)

        _write_summary(_summary("COMPLETE", 0, [], len(output), "MEASURED", output))
        return 0
    except (InputRefused, OSError, ValueError, UnicodeError):
        _write_summary(_summary("INPUT_REFUSED", 2, ["INPUT_MANIFEST_REFUSED"], None, "NOT_MEASURED", []))
        sys.stderr.write("INPUT_MANIFEST_REFUSED\n")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
