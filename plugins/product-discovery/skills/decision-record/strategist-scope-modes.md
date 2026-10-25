# Strategist Scope Modes

Use one `scope_mode` to describe the boundary proposed for the existing task. A mode is a scope description, not an outcome, approval, permission, or route. A `GO` recommendation under any mode does not authorize execution or bypass the task's acceptance and authority checks.

| Mode | Meaning | Required scope note |
|---|---|---|
| `hold` | Keep the current boundary unchanged. | State what remains in and out of scope. |
| `selective` | Keep only named portions of the current proposal. | List retained work and the parts deferred or removed. |
| `expand` | Add a bounded item needed to reach the stated outcome. | Name the added work and the reason it is necessary. |
| `reduce` | Remove named work while retaining a smaller outcome. | List removed work and what the reduced result still delivers. |

Every v2 strategist record includes `scope_delta` and `do_nothing_cost`. Describe the expected cost of leaving the task unchanged when it is supported; record `unknown` when it has not been measured. Do not estimate it as zero merely because no measurement exists.

Record the business outcome (`continue`, `pivot`, `stop`, or `more-evidence`) separately from `scope_mode`. Record evidence acceptance and authority to act separately as well. A mode does not select the outcome, approve the proposed scope, or grant authority.
