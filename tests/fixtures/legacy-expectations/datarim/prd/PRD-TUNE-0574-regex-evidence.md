# Frozen excerpt — PRD-TUNE-0574 task-prefix regex evidence

Historical record, frozen as a test fixture. The product root no longer carries a
`datarim/` knowledge base: that content is data, not framework tooling, and the
project-scoped migration removed it from the shipped tree. The two lines below are
the only part the regression test needs — evidence that the pre-TUNE-0574 records
used the letters-only task-prefix form, which shipped surfaces must no longer use.

Do not 'modernise' these lines: their value is that they are frozen.

> - **ID detection inside hatch**: uses POSIX lexical-boundary checks around `[A-Z]{2,10}-[0-9]{4}` (no `\b` reliance). A valid hatch is a syntactic exemption for a reviewed illustrative block; the gate does not pretend it can infer whether an arbitrary token is historically real.
> If such a line binds on the same or next continuation line to a token matching `[A-Z]{2,10}-[0-9]{4}`, the file fails. The check must handle common Markdown decoration and label case variants.
