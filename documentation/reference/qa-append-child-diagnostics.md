# QA append failure diagnostics

The P2.5 parallel-append test prints its child-process diagnostic only when an
existing assertion fails. The diagnostic adds bounded evidence for the two
append command processes whose PIDs the test parent captured, and for their
four fixed synthetic stdout and stderr files.

## Fields

The diagnostic retains the existing exit, validator, fixture, heading, marker,
and fixture-snapshot fields. It also emits:

| Field | Meaning |
| --- | --- |
| `child_1_pid`, `child_2_pid` | Parent-observed child PIDs captured from the shell's `$!`; absent or invalid values are `NOT_MEASURED`. |
| `child_1_exit`, `child_2_exit` | Exit status observed by the parent when it waited for each child. |
| `<child>_<stream>_availability` | `available` for a successfully measured regular file, or a fixed `unavailable:<reason>` value. |
| `<child>_<stream>_bytes` | Byte count when the complete stream measurement succeeds; otherwise `NOT_MEASURED`. |
| `<child>_<stream>_sha256` | SHA-256 digest when the complete stream measurement succeeds; otherwise `NOT_MEASURED`. |
| `<child>_<stream>_prefix_hex` | Hex encoding of at most the first 64 stream bytes; raw stream text is never printed. |
| `<child>_<stream>_prefix_truncated` | `yes` when more than 64 bytes were present, `no` otherwise, and `NOT_MEASURED` when the stream could not be measured. |

`<child>` is `child_1` or `child_2`; `<stream>` is `stdout` or `stderr`.
Only the four fixed stream filenames in the test's temporary fixture directory
are eligible. Missing, unreadable, symlinked, non-regular, or failed-read
streams are reported as unavailable; they are not treated as empty files.
An available empty file has a zero byte count, the SHA-256 digest of empty
content, an empty hex prefix, and `prefix_truncated=no`.

Child metadata precedes the fixture snapshot so it is retained when the
diagnostic reaches its 4096-byte total output cap. The output ends with an
explicit truncation field. Stream prefixes are hex encoded and bounded
separately; fixture snapshot encoding and limits remain as before.

## Interpretation and privacy limits

These fields make already-captured test streams inspectable without printing
their raw text or filesystem paths. They do not show which process or
filesystem interleaving caused a missing append, and they do not establish
lock acquisition, append, or rename ordering. A CI failure still requires its
own source and execution evidence; this diagnostic is not a reproduction of a
prior run and does not change the append helper or its success behavior.

Synthetic callers that use the existing five-argument diagnostic form remain
supported. When no parent-observed PIDs or child stream files are supplied,
those fields are reported as unavailable or `NOT_MEASURED` rather than
invented.
