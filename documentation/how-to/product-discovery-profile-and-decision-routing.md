# How to Select Product Discovery and Route a Decision

This how-to explains how to select the Product Discovery profile for one task, confirm that the plugin is enabled, and read the canonical decision router's next step. It uses the task settings and output names recognized by the current source.

## Select the profile and enable the plugin

Product Discovery is applied only when the task has one selector under the `## Profile` heading and the plugin is enabled in the workspace.

In `datarim/tasks/{TASK-ID}-task-description.md`, add the selector as a body section:

```markdown
## Profile
profile: product-discovery
```

The reader looks for exactly one `profile: product-discovery` line under `## Profile`. Text elsewhere in the task, including task frontmatter, does not select the profile. Do not add a second selector line.

Enable the plugin from the Datarim source checkout:

```bash
scripts/dr-plugin.sh enable /absolute/path/to/plugins/product-discovery
```

The workspace setting is `datarim/enabled-plugins.md`; the plugin must appear under `## Active` as:

```markdown
## Active
- id: product-discovery
```

Selection and enablement are separate settings. Enabling the plugin alone does not select it for a task.

## Check the selected profile

Run the persisted-profile reader with the workspace root and task ID:

```bash
bash "${DATARIM_RUNTIME:?}/dev-tools/read-product-profile.sh" \
  --root <workspace-root> \
  --task <TASK-ID> \
  --runtime "${DATARIM_RUNTIME:?}"
```

The reader prints one result:

| Result | Meaning and next step |
| --- | --- |
| `profile_active` | The task selector is present, the plugin is active, and the installed entry skill is readable. Only this result applies Product Discovery guidance. |
| `profile_not_selected` | No selector was found under `## Profile`; the default discovery route continues unchanged. |
| `profile_unavailable` | The profile is selected, but the plugin is not active or its installed entry skill is unreadable. Follow the default route; the command surface emits its unavailable notice. |
| `profile_unknown` | The selector names another profile. Follow the default route and inspect the selector value. |
| `profile_ambiguous` | More than one selector line was found. Follow the default route and leave one intended selector. |

These results report configuration only. They do not validate research evidence or grant authority to act.

## Read the active DecisionRecord route

For an active Product Discovery profile, run the canonical router:

```bash
python3 "${DATARIM_RUNTIME:?}/dev-tools/product-decision-route.py" \
  --root <workspace-root> \
  --task <TASK-ID>
```

Read its JSON `route` and `token`; when present, use `detail` to identify the refusal reason. The router accepts these active DecisionRecord `status` values:

| Active `status` | Router behavior |
| --- | --- |
| `draft` | Returns `PRODUCT_ROUTE_EVIDENCE_PENDING` for `/dr-qa`; the research record is incomplete and no delivery work is created. |
| `submitted` | This status alone does not advance. The DecisionRecord must also have accepted acceptance/evidence fields. A continue outcome additionally requires the matching accepted ProductBrief, granted `authority_to_act`, and a matching scope advance tied to the unchanged parent acceptance contract. Otherwise follow the returned pending route or typed refusal. |
| `superseded` | Returns `PRODUCT_ROUTE_SUPERSEDED` for `/dr-do`; the active revision is stale and creates no delivery work. |

`accepted` is not a DecisionRecord `status`; it is used in separate acceptance fields. Do not change one field to stand in for another.

## Handle typed refusals and incomplete results

- If the router returns a `PRODUCT_REFUSE_*` token, follow its `route` to `/dr-status`. The router does not create a PRD on a refusal.
- For an unsupported active DecisionRecord status, the router returns `PRODUCT_REFUSE_ARTIFACT_INVALID` with `detail: E_STATUS_INVALID` and route `/dr-status`. Inspect the active artifact's `status` and validate the artifact using the structural checker. Do not treat the refusal as a pending route or continue to PRD.
- To validate the active bundle, use the checker command documented in the [Product Discovery README](../../plugins/product-discovery/README.md#structural-checker):

  ```bash
  bash "${DATARIM_RUNTIME:?}/dev-tools/check-product-artifact.sh" \
    --root <bundle-root> \
    --bundle <bundle-directory>
  ```

- For `PRODUCT_ROUTE_EVIDENCE_PENDING`, use `/dr-qa` as returned; do not create delivery work while evidence remains pending. For `PRODUCT_ROUTE_STOP`, report the accepted stop through `/dr-archive` without delivery. `PRODUCT_ROUTE_PIVOT` and `PRODUCT_ROUTE_MORE_EVIDENCE` remain incomplete in `/dr-do` without delivery.
- DecisionRecord and ProductBrief revisions are immutable. When a correction requires a new revision, preserve the prior file and set the new revision's `supersedes` reference as described in the [Product Discovery README](../../plugins/product-discovery/README.md#runtime-storage-and-routing).

## Source references

- [Persisted profile reader](../../dev-tools/read-product-profile.sh)
- [Canonical decision router](../../dev-tools/product-decision-route.py)
- [PRD command routing contract](../../commands/dr-prd.md)
- [Product Discovery README](../../plugins/product-discovery/README.md)
