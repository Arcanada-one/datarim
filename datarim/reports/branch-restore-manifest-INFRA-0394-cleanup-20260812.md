# Datarim remote-branch cleanup — restore manifest & verdicts (2026-08-12)

Repo: `Arcanada-one/datarim`. Baseline: `origin/main` = `939a728` (PR #369 merged).
Executed by the Datarim-alignment lane on arcana-devs. Evidence sources:
INFRA-0394 adjudication (`/home/dev/INFRA-0394-results/work-datarim/verdicts.tsv`,
blob-presence method) independently spot-checked by content diff against
`origin/main`; PR #369 body; first-pass file-level content scan (all 50 branches).

**Restore recipe:** content-preserved branches → `git fetch origin tag <zz-archived-tag>`,
then `git branch <name> <sha>`. Deleted-as-landed branches → the SHA below is
unreachable after GitHub GC; their content lives on `main` (verdict column says where).

## Preserved under zz-archived/* tags before deletion (genuinely-unmerged work)

| Branch | SHA | Tag | Why kept |
|---|---|---|---|
| rescue/INFRA-0394/batch-a-framework-rules | bc3e461c81ca073d13a693d2d522fb91e3ece3de | zz-archived/rescue/INFRA-0394/batch-a-framework-rules-20260812 | 9 conflicts vs main incl. security-gate logic; needs owning task (backlog TUNE-0592) |
| rescue/INFRA-0394/batch-c-framework-rules | bf9d0e7ff0ef7ec143be52069631cebd244859c6 | zz-archived/rescue/INFRA-0394/batch-c-framework-rules-20260812 | 6 conflicts; needs owning task (backlog TUNE-0592) |
| rescue/INFRA-0394/batch-d-framework-rules | 145e3d57601f88f3781ca1a84df18e5442d7b915 | zz-archived/rescue/INFRA-0394/batch-d-framework-rules-20260812 | 4 conflicts; partial landing = red suite (backlog TUNE-0592) |
| tune-0103-work | 549915802a706ca9f5af9ba6917220c7fd35de56 | zz-archived/tune-0103-work-20260812 | LTM-graph plugin absent from main; backlog TUNE-0103 pending P2 |
| tune-0105-coworker-delegation-toggle | a46872d27ce1cfc0407d0ad0d0694d2e0a867fc7 | zz-archived/tune-0105-coworker-delegation-toggle-20260812 | TUNE-0105 cancelled-obsolete in backlog, but plugin variant never landed — tag keeps the option |
| tune-0139-work | 23466198c6775de4037efa37f58b0c11e03bc1b2 | zz-archived/tune-0139-work-20260812 | auto-fix gated on unrecorded FP rate; backlog TUNE-0139 pending («branch preserved» promise now points at the tag) |
| tune-0140-work | 1bb8b986d47f6ec9b701c9547f158378371be36a | zz-archived/tune-0140-work-20260812 | 889/889 added lines absent from main; backlog TUNE-0140 pending |
| tune-0306-work | 3f31f3aa155884547b8e42338ca5c75ec3bf807c | zz-archived/tune-0306-work-20260812 | codex-prompts install feature, 6 conflicts vs today's install.sh; backlog TUNE-0306 pending («READY FOR Mac PR» — worktree ~/.worktrees/datarim/tune-0306 still on arcana-devs) |
| tune-0396-work | 9d93d293d28716d358116b6b235055e62710120c | zz-archived/tune-0396-work-20260812 | init-task-persistence hunk conflicts; backlog TUNE-0396 pending |
| rescue/INFRA-0394/tune-batch-epic-e | b227cdf1194ef14f08041d41328ffaa453d78761 | zz-archived/rescue/INFRA-0394/tune-batch-epic-e-20260812 | strict subset of epic-f; carries gitleaks fixture cli-audit-fixture.jsonl (allowlisted by path in .gitleaks.toml — keep the entry while the tag exists) |
| rescue/INFRA-0394/tune-batch-epic-f | b9e7af70b610019f52ce13961d8b872ceeee0bfc | zz-archived/rescue/INFRA-0394/tune-batch-epic-f-20260812 | unique units landed by PR #369; tag kept because the epic also contains the stacked 0103/0105/0139/0140 base and TUNE-0198/0239 material not separately adjudicated; still checked out in the shared clone ~/arcanada/Projects/Datarim/code |

## Landed via PR before deletion

| Branch | SHA | Disposition |
|---|---|---|
| rescue/INFRA-0394/tune-0578-framework-report-finish | 310365d5506e495f998180806e9120f45f75505b | its single unlanded file `documentation/archive/framework/archive-TUNE-0530.md` lands in the v2.66.0 release PR; branch deleted after merge |

## Deleted — content verified on main

Evidence classes: `LANDED-#369` = recovered by PR #369; `LANDED-content N%` = INFRA-0394
blob-presence (deletions still_in_main=0); `SUPERSEDED` = feature reached main by
another route with equal-or-newer content; `TREE≡main` = tree diff vs the squash
commit on main is empty (verified directly).

| Branch | SHA | Verdict |
|---|---|---|
| fix/content-0061-telegram-contract | 801ab4aef4485e07dde61672def75a0181f9788a | LANDED-#369 (Telegram article contract, conflict resolved keep-both) |
| reconcile/INFRA-0202-signed-state | 1b94886b577ff749ee9f056ec5ce73c7f464d19c | 0 files differ from main |
| rescue/ARCA-0194-r6-02-caller-contract-20260810-ade3681 | ade368160317d1c3dfbb55cb96a91ac249f0d985 | TREE≡main (squash aa254af, PR #359) |
| rescue/main-20260811 | ade368160317d1c3dfbb55cb96a91ac249f0d985 | same SHA as above |
| rescue/INFRA-0394/INFRA-0355 | c2e86df903e84991c6ebd97aede03ba077339163 | SUPERSEDED (corepack provisioning in reusable-security-audit.yml) |
| rescue/INFRA-0394/RELAND-0368 | 949ef4df3b66d4c60a94bdb05784af80e9c202d7 | abandoned reland with conflict markers; underlying TUNE-0367/0422/0505/0507/S11 all on main (verified: exempt clause in fragment, S11 in CLAUDE.md, session-execution-drift-warn.sh linked by install.sh) |
| rescue/INFRA-0394/feat/ltm-0022-known-fix-hooks | 228bd18ac9b423dbfa19c2e4e051fa5dc171ad58 | LANDED-content 100% |
| rescue/INFRA-0394/sweep/ARCA-0168-webhook-preflight | 6e3885fc4fc536365912a8640853f49de552f3d6 | LANDED-content 100% |
| rescue/INFRA-0394/tune-0153-work | ff074c3a512e2bfde768b19b3fd526b157a3a757 | LANDED-content 93% (residual superseded) |
| rescue/INFRA-0394/tune-0191-work | 0e7287b5618f724c809c478c139df9ebd7cc71ae | LANDED-content 95% |
| rescue/INFRA-0394/tune-0240-work | a9335a4e01650c3bf6d9c2e48b69c76f74e7f6eb | LANDED-content 100% |
| rescue/INFRA-0394/tune-0270-work | f70240a8283d82421239228200085bd338f986c8 | LANDED-content 100% |
| rescue/INFRA-0394/tune-0285-work | 298932393760db409cf1252d4b31a66b56a205ee | LANDED-content 95% |
| rescue/INFRA-0394/tune-0292-work | bdfafa211193b050dfdc14fbada031536a64b842 | LANDED-content 94% — independently spot-checked: residual = doc paragraphs main rewrote (history-agnostic) + bats main extended |
| rescue/INFRA-0394/tune-0300-work | 3891ab98e741751bedb33301b8aae04cad244928 | LANDED-content 95% |
| rescue/INFRA-0394/tune-0367-work | 1ddce93a56659987361d551a669844db7da21961 | LANDED-content 100% |
| rescue/INFRA-0394/tune-0368-work | d4ca3848e085469ab59c3ef1bd335ed06c162aa2 | LANDED-content 99% |
| rescue/INFRA-0394/tune-0389-work | 93cd34ea1ef5a1fb1020fceb26cf063fff6d997d | LANDED-content 100% |
| rescue/INFRA-0394/tune-0390 | a25e4bd317a996f359662c652f24d99e8a154db5 | LANDED-content 97% |
| rescue/INFRA-0394/tune-0406-staleness-probe | e23797da84ab33ca33ad68a5fe25735a4d2ddf1d | SUPERSEDED (probe in dr-init/dr-plan + bats on main) |
| rescue/INFRA-0394/tune-0422-work | 2bdbd63b2758816606c189e19125a2f731faad9c | LANDED-content 99% |
| rescue/INFRA-0394/tune-r4-epic | af779e9d755e48cdc83c9bc87feba685a5824d70 | SUPERSEDED (dev-tools-lint.yml + bats on main) |
| rescue/INFRA-0394/tune-r6-epic | 5e3c8e5593e280c90dc2ab8fac9e34a413900160 | only CHANGELOG wording differs; rotation-runbook skill on main |
| tune-0102-tdd-enforcement-toggle | ad2759d89bc93ef889826de0f938b3bb8f42c2eb | SUPERSEDED (shipped as core-owned plugin, plugins/tdd-enforcement on main) |
| tune-0115-work | c21b3ddcf900c81dfac61ca7cbfe1fadea3935ee | SUPERSEDED (skill split re-done as adversarial-review/edge-case-hunter/structure-review, landed #369) |
| tune-0125-work | 0e37770657b4ca8ffc25589b8b651ab8f84574dd | SUPERSEDED (local-overlay override check in validate.sh) |
| tune-0138-self-verification-hooks | e9fa893213a1a81da0f8dda987b86f5db350bb3b | SUPERSEDED (post-step self-verification hook on main; residual = 0103/0105 stack) |
| tune-0153-work | ff074c3a512e2bfde768b19b3fd526b157a3a757 | duplicate of rescue copy, LANDED-content 93% |
| tune-0181-work | a21b6cab2c1cf5b80ad04d9c9d5c14d859dd1ec0 | SUPERSEDED (v-ac-feasibility skill wired on main) |
| tune-0265-work | fc773b26ef62d048eb9fe931287f2185deacdfc9 | SUPERSEDED (validate-qa-blocks.awk landed #369; rest newer on main) |
| tune-0289-work | 956e9771877c392a1d3ae6a35b9855df2b706865 | SUPERSEDED (accepted-risk AAL gate on main) |
| tune-0294-prd-amendment | 39a19f45abeae4f073ac5f16d9643618f5602cfb | SUPERSEDED (PRD-amendment sidecars on main; residual = stacked base) |
| tune-0299-work | e2d37f9d552bc36f87da56f3ab67fc7253c33a48 | SUPERSEDED (semantic-parser bats + rules/default.yaml on main) |
| tune-0301-work | 716c147fc648c73b93a751e4da7c06906db8dfc2 | LANDED-#369 (Datarim MCP server + registrar) |
| tune-0370-work | e9e46c860080c6d81c76a4a43a72371296bf3632 | LANDED-#369 (editor/writer/factcheck hunks) |
| tune-0375-work | 1bb4a4926c6409ce9e903f798b7275af4b99a192 | LANDED-content 95% |
| tune-0405-work | 6559becbfd928054f112bedd9ac1865163d0321b | SUPERSEDED (stage-snapshot feature on main, newer) |
| tune-0407-work | db6a61d620a51c565664462e02511651a1c16ea7 | SUPERSEDED (network-exposure gate + skill on main, newer) |
| tune-0475-work | 23c9d5c0f1fbf99d9ccc0e5d0d182c994ee4f19b | SUPERSEDED (balance-provider bats on main, newer) |

## Local branches on arcana-devs (~/arcanada/Projects/Datarim/code/datarim)

| Branch | SHA | Verdict |
|---|---|---|
| fix/ARCA-0194-preflight-time-observability | 2a252f8 | content superseded by squashes #362/#363/#365 (verified: 5 branch-side lines are older variants) — deleted |
| tune-0578-framework-report-finish | 1f494f4 | TREE≡main (squash 2df519f, PR #361) — deleted |
| tune-r5-a1/a2/b1/b2/g/s, tune-r5-release-2.63.0 | — | released in v2.63.0 (tag exists); zz-archived/tune-r3/r4/r6 precedent tags cover the round-branch pattern — deleted after ancestry/content check |
| tune-r6-epic, tune-r6-release | 5e3c8e5, 03037bc | v2.64.0 released; remote rescue copy verdict above — deleted |
| tune-r7-epic | f88132e | round-7 released as v2.65.0 — deleted after content check |
| main | 939a728 | reset to origin/main (was ade3681, TREE≡main via #359) |

Third clone `~/arcanada/Projects/Datarim/code` (checked out on tune-batch-epic-f) is
IN USE by parallel sessions — not touched (workspace discipline). Its branch's remote
copy is preserved by the epic-f tag above.
