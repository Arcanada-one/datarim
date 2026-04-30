---
name: release-verify
description: Consumer-side recipe для Datarim release — sha256 → cosign verify-blob → gh attestation verify. Load при install/update из GitHub Release.
---

# Release Verify — Consumer-Side Verification Recipe

Datarim релизы публикуются `Arcanada-one/datarim` через `release.yml` (TUNE-0050) и подписаны Sigstore cosign keyless (GitHub OIDC) + сопровождаются CycloneDX SBOM и SLSA L2 build provenance attestation. **Никогда не устанавливай tarball без проверки подписи.**

Этот skill — точка входа для AI-агентов и операторов, потребляющих Datarim релизы. Канонический источник правды: [`docs/release-verification.md`](../docs/release-verification.md). Этот skill дублирует core recipe, чтобы агент мог ответить пользователю без дополнительного fetch.

## When To Use

Загружай этот skill, когда:

- Пользователь говорит «установи Datarim», «обнови до v*», «скачай latest release».
- Пользователь спрашивает «как проверить tarball», «что такое cosign bundle», «зачем sha256 если есть подпись».
- Любая инструкция, которая включает `gh release download Arcanada-one/datarim` или эквивалент.
- Перед запуском любого install-скрипта из release tarball.

Не загружай для git-checkout / `git pull` рабочих копий — там верификация осуществляется через git commit signing (отдельная политика).

## What Ships per Release

| Файл | Назначение |
|---|---|
| `datarim-<TAG>-source.tar.gz` | Source archive (`git archive HEAD`, prefix `datarim-<TAG>/`). |
| `datarim-<TAG>-source.tar.gz.sha256` | SHA-256 checksum. |
| `datarim-<TAG>-source.tar.gz.cosign.bundle` | Cosign signature bundle (cert + signature + Rekor inclusion proof). |
| `datarim-<TAG>-sbom.cdx.json` | CycloneDX SBOM. |
| `datarim-<TAG>-sbom.cdx.json.cosign.bundle` | Cosign signature на SBOM. |
| GitHub attestation (server-side) | SLSA L2 build provenance, через `gh attestation verify`. |

## Prerequisites

- [`cosign`](https://docs.sigstore.dev/cosign/installation/) ≥ 3.0
- [`gh`](https://cli.github.com/) ≥ 2.40 (для `gh attestation verify`)
- `sha256sum`, `jq` (POSIX)

## Verify Recipe (5 steps, all must exit 0)

```bash
TAG=v1.18.0   # замени на проверяемый релиз

# 1. Скачать все артефакты релиза.
gh release download "$TAG" --repo Arcanada-one/datarim

# 2. Проверить целостность tarball через checksum.
sha256sum -c "datarim-${TAG}-source.tar.gz.sha256"

# 3. Проверить cosign signature на tarball.
cosign verify-blob \
  --bundle "datarim-${TAG}-source.tar.gz.cosign.bundle" \
  --certificate-identity "https://github.com/Arcanada-one/datarim/.github/workflows/release.yml@refs/tags/${TAG}" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  "datarim-${TAG}-source.tar.gz"

# 4. Проверить cosign signature на SBOM (тот же identity binding).
cosign verify-blob \
  --bundle "datarim-${TAG}-sbom.cdx.json.cosign.bundle" \
  --certificate-identity "https://github.com/Arcanada-one/datarim/.github/workflows/release.yml@refs/tags/${TAG}" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  "datarim-${TAG}-sbom.cdx.json"

# 5. Проверить SLSA build provenance.
gh attestation verify "datarim-${TAG}-source.tar.gz" --repo Arcanada-one/datarim
```

Любой non-zero exit → артефакт **untrusted**, не разворачивать.

## What Each Step Proves

| Шаг | Свойство |
|---|---|
| `sha256sum -c` | Integrity. Tarball не повреждён в транзите. |
| `cosign verify-blob` (tarball) | Authenticity. Tarball произведён `release.yml` именно на этом tag в `Arcanada-one/datarim`. Signature anchored в [Sigstore Rekor](https://search.sigstore.dev/) public transparency log. |
| `cosign verify-blob` (SBOM) | SBOM произведён той же workflow run, что и tarball. |
| `gh attestation verify` | SLSA L2 build provenance — артефакт собран GitHub-hosted runners из source на этом tag. |

`cosign verify-blob` — это шаг, который связывает tarball с build origin. Sha256 без cosign не доказывает ничего: атакующий заменит и архив, и `.sha256`-файл одновременно.

## Counter-Examples (do not do this)

<!-- security:counter-example -->
```bash
# DO NOT — пропускает проверку подписи целиком.
curl -sL "https://github.com/Arcanada-one/datarim/releases/download/v1.18.0/datarim-v1.18.0-source.tar.gz" \
  | tar -xz
```
<!-- /security:counter-example -->

<!-- security:counter-example -->
```bash
# DO NOT — проверяет только checksum, который атакующий подменит вместе с tarball.
gh release download v1.18.0 --repo Arcanada-one/datarim
sha256sum -c "datarim-v1.18.0-source.tar.gz.sha256"   # сам по себе ничего не доказывает, если .sha256 тоже подделан
tar -xzf "datarim-v1.18.0-source.tar.gz"
```
<!-- /security:counter-example -->

<!-- security:counter-example -->
```bash
# DO NOT — cosign без --certificate-identity принимает подпись от любого signer-а
# (любой OIDC subject из issuer может выпустить cert и подписать произвольный tarball).
cosign verify-blob \
  --bundle "datarim-v1.18.0-source.tar.gz.cosign.bundle" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  "datarim-v1.18.0-source.tar.gz"
```
<!-- /security:counter-example -->

## Troubleshooting

| Симптом | Причина / fix |
|---|---|
| `cosign verify-blob` → `no matching signatures` | `--certificate-identity` не совпадает с `release.yml@refs/tags/<TAG>` из подписавшего workflow. Проверь точный TAG, capitalization org/repo. |
| `gh attestation verify` → `no attestations found` | Релиз создан до TUNE-0050 (release.yml landing 2026-04-29) или вручную. Только теги, прошедшие через `release.yml`, имеют SLSA L2 attestation. |
| `sha256sum: WARNING: 1 computed checksum did NOT match` | Tarball повреждён или подменён в транзите. Скачай заново; если воспроизводится — открой issue. |
| `gh: command not found` | Установи [GitHub CLI](https://cli.github.com/) ≥ 2.40 — нужен только для шага 5 (attestation verify); шаги 1-4 можно сделать через `curl` + `cosign`. |

## Reporting Verification Failures

Если `cosign verify-blob` или `gh attestation verify` падает на официальном release tag — **не устанавливай**. Открой issue в `https://github.com/Arcanada-one/datarim/issues` с tag-ом, командой и её output. Это потенциальный supply-chain инцидент.

## Source of Truth

- Канонический recipe: [`docs/release-verification.md`](../docs/release-verification.md) (пользовательская страница).
- Workflow, выпускающий артефакты: [`.github/workflows/release.yml`](../.github/workflows/release.yml) (TUNE-0050).
- Security Mandate § S4 (Supply Chain): [`CLAUDE.md`](../CLAUDE.md#security-mandate).
- Sigstore cosign docs: https://docs.sigstore.dev/cosign/
- SLSA spec: https://slsa.dev/

При расхождении этого skill с `docs/release-verification.md` — `docs/release-verification.md` побеждает; обнови skill.
