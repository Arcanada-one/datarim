# QA append I/O failures

`dev-tools/append-init-task-qa.sh` appends a Q&A block to the selected
init-task file by building a temporary file and replacing the original after
the append is complete.

## Result meanings

- Exit `0` means the replacement completed and the Q&A block was appended.
- Exit `1` means validation or I/O failed. If the final replacement command
  refuses the prepared file, the helper reports that failure and retains the
  temporary-file path for its exit cleanup instead of reporting success.
- Exit `2` means the invocation has a usage error.

Every value-taking option requires a following argument. If an option that
takes a value is the final argument, the helper reports a usage error and exits
`2`; it does not enter validation or file-writing work.

The one-line `--summary`, `--asked-by`, and supplied `--timestamp` fields reject
embedded line feeds, carriage returns, and C0/C1 control characters with usage
exit `2`, before lock or temporary-file work. Printable UTF-8, including
Cyrillic text, arrows, and em dashes, remains accepted. Bash arguments cannot
contain NUL bytes, so the CLI cannot receive or test a NUL value.

On a failed final replacement, the original init-task file remains the
committed version; the helper attempts to remove its temporary file and release
the task lock during exit cleanup. This describes the helper's controlled
failure path. It does not guarantee cleanup when the filesystem refuses cleanup
too, nor does it establish a universal atomicity guarantee across signals or
filesystem failures.

The append helper serializes writers through its per-task lock. This I/O
failure handling does not establish or claim a cause or fix for any observed
parallel content-loss incident.

## Control-scan tool errors

The one-line checks distinguish a matching control byte, an ordinary no-match,
and a failed scan command. A match remains a usage refusal (exit `2`). Only
exit `1` from each scan means “no match”; any other scan status stops the
helper with exit `1` and a fixed I/O diagnostic before task-file, lock, or
temporary-file operations. Scanner error text and the supplied field value are
not copied into that diagnostic.

`tests/qa-append-io-failures.bats` contains focused cases for an execution
failure in each scan and a printable UTF-8 append through the same guard path.
These checks cover the guard's tool-error boundary; they do not assert a cause
for a prior parallel append incident.
