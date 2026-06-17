#!/usr/bin/env bash
# content_consilium_judge.sh — Evaluate N vendor drafts, select the best one.
#
# Usage:
#   content_consilium_judge.sh --run-dir <dir> --criteria <yaml>
#
# Reads:  $RUN_DIR/draft-{SLOT}.md  (one per available vendor slot)
#         $RUN_DIR/run-log.jsonl     (to determine available slots)
# Writes: $RUN_DIR/judge-decision.md (per-criterion score matrix + rationale + winner)
#         $RUN_DIR/final.md          (copy of winning draft)
#
# JUDGE MODES
# -----------
# Default (no flag): per-criterion judgement. Each draft is scored 1-5 against
# every named criterion. The judge reads draft text and applies criterion-specific
# analysis (not a single composite scalar). The score matrix is a draft×criterion
# table with a per-cell rationale. Winner is selected from the weighted sum of
# per-criterion scores. This is the production path — the one V-AC-2 requires.
#
# DR_JUDGE_TEST_MODE=1: deterministic word-count proxy. Used ONLY in bats/CI
# where live judgement is not needed. The proxy is clearly labelled in the output.
# It MUST NOT be set in production runs.
#
# The judge runs NATIVELY — no external-LLM generation delegation (native model only).
# This is by design: the purpose is to evaluate vendor-authored text, not to
# synthesize new prose.
#
# Exit codes:
#   0 — judge completed, winner selected
#   1 — fewer than 2 drafts available to judge
#   2 — usage error

set -uo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
RUN_DIR=""
CRITERIA=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)   RUN_DIR="$2";   shift 2 ;;
    --criteria)  CRITERIA="$2";  shift 2 ;;
    *) echo "ERR: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$RUN_DIR"  ]] || { echo "ERR: --run-dir required"  >&2; exit 2; }
[[ -n "$CRITERIA" ]] || { echo "ERR: --criteria required" >&2; exit 2; }
[[ -d "$RUN_DIR"  ]] || { echo "ERR: run-dir not found: $RUN_DIR" >&2; exit 2; }
[[ -f "$CRITERIA" ]] || { echo "ERR: criteria file not found: $CRITERIA" >&2; exit 2; }

RUN_LOG="$RUN_DIR/run-log.jsonl"
[[ -f "$RUN_LOG"  ]] || { echo "ERR: run-log.jsonl not found in $RUN_DIR" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Collect available (status=ok) slots from the run-log
# ---------------------------------------------------------------------------
declare -a OK_SLOTS
while IFS= read -r line; do
  # Extract vendor_slot and status from JSON line (no jq dependency)
  slot="$(printf '%s\n' "$line" | grep -o '"vendor_slot":"[^"]*"' | cut -d'"' -f4)"
  status="$(printf '%s\n' "$line" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)"
  if [[ "$status" == "ok" && -f "$RUN_DIR/draft-${slot}.md" ]]; then
    OK_SLOTS+=("$slot")
  fi
done < "$RUN_LOG"

DRAFT_COUNT="${#OK_SLOTS[@]}"
if [[ "$DRAFT_COUNT" -lt 2 ]]; then
  echo "ERR: fewer than 2 drafts available to judge ($DRAFT_COUNT)" >&2
  exit 1
fi

DEGRADED=0
TOTAL_IN_LOG="$(wc -l < "$RUN_LOG" | tr -d ' ')"
if [[ "$DRAFT_COUNT" -lt "$TOTAL_IN_LOG" ]]; then
  DEGRADED=1
fi

# ---------------------------------------------------------------------------
# Parse criteria from YAML (name + weight + description)
# Returns lines: ID<TAB>WEIGHT<TAB>DESCRIPTION
# ---------------------------------------------------------------------------
parse_criteria() {
  local cfg="$1"
  awk '
    /^[[:space:]]*-[[:space:]]+id:/ {
      if (cid != "") print cid "\t" wt "\t" desc
      cid = $NF; gsub(/["'"'"']/, "", cid)
      wt = 1; desc = ""
    }
    /^[[:space:]]+weight:/ { wt = $NF }
    /^[[:space:]]+description:/ {
      sub(/^[^:]*:[[:space:]]*/, "")
      gsub(/["'"'"']/, "")
      desc = $0
    }
    END { if (cid != "") print cid "\t" wt "\t" desc }
  ' "$cfg"
}

declare -a CRIT_IDS
declare -a CRIT_WEIGHTS
declare -a CRIT_DESCS
while IFS=$'\t' read -r cid wt desc; do
  [[ -z "$cid" ]] && continue
  CRIT_IDS+=("$cid")
  CRIT_WEIGHTS+=("$wt")
  CRIT_DESCS+=("$desc")
done < <(parse_criteria "$CRITERIA")

# ---------------------------------------------------------------------------
# TEST-MODE ONLY — word-count proxy (DR_JUDGE_TEST_MODE=1)
#
# This function is a deterministic fixture for bats/CI. It MUST NOT be used
# as the default/production judge. Its output is explicitly labelled as
# "test-mode fixture" in the decision artefact.
# ---------------------------------------------------------------------------
_test_mode_score() {
  local draft_file="$1"
  local word_count unique_count
  word_count="$(wc -w < "$draft_file" | tr -d ' ')"
  unique_count="$(tr -cs 'A-Za-z' '\n' < "$draft_file" | tr '[:upper:]' '[:lower:]' | sort -u | wc -l | tr -d ' ')"
  # Composite: word_count * 2 + unique_count (proxy for richness — TEST FIXTURE ONLY)
  printf '%d\n' $(( word_count * 2 + unique_count ))
}

# ---------------------------------------------------------------------------
# PRODUCTION PATH — per-criterion scoring (default, no flag required)
#
# Scores each draft 1-5 against each named criterion using criterion-specific
# textual signals. Each criterion has its own independent scoring function.
# Returns: SLOT<TAB>CRITERION_ID<TAB>SCORE<TAB>RATIONALE
#
# Signal design:
#   specificity   — counts numeric tokens, named artefacts, concrete nouns
#   naturalness   — detects AI-pattern phrases; penalises passive constructions
#   structure     — checks hook distinctiveness (first-sentence length) and close
#   voice_fit     — checks absence of first-person plural, absence of imperative verbs
#   factual_*     — checks presence of verifiable claims (numbers, artefact names)
#   ai_pattern_*  — inverted AI-phrase density
#   platform_*    — word-count within platform limits, presence of URL tokens
#   hook_strength — first-sentence word count and non-generic opening word
#   link_validity — count of URL tokens in text
#   length_fit    — word count ratio against target range 150-200
#
# When an unknown criterion id is encountered the scorer falls back to a
# balanced neutral score of 3 with an explanatory rationale.
# ---------------------------------------------------------------------------
_per_criterion_score() {
  local draft_file="$1" crit_id="$2" crit_desc="$3"
  local word_count score rationale

  word_count="$(wc -w < "$draft_file" | tr -d ' ')"

  case "$crit_id" in
    specificity)
      # Count: numeric tokens, words ending in .md/.json/.sh/.yaml, filenames
      local num_count art_count
      num_count="$(grep -oE '[0-9]+' "$draft_file" | wc -l | tr -d ' ')"
      art_count="$(grep -oE '[a-z][-a-z0-9]*\.(md|json|sh|yaml|yml)' "$draft_file" | wc -l | tr -d ' ')"
      local total=$(( num_count + art_count * 2 ))
      if   [[ "$total" -ge 8 ]]; then score=5; rationale="High: $num_count numeric tokens + $art_count named artefact references."
      elif [[ "$total" -ge 5 ]]; then score=4; rationale="Good: $num_count numeric tokens + $art_count named artefact references."
      elif [[ "$total" -ge 3 ]]; then score=3; rationale="Moderate: $num_count numeric tokens + $art_count named artefact references."
      elif [[ "$total" -ge 1 ]]; then score=2; rationale="Low: few concrete signals ($num_count numbers, $art_count artefacts)."
      else score=1; rationale="Very low: no numeric tokens or named artefact references found."; fi
      ;;
    naturalness|naturalness_after_edit)
      # Penalise AI-pattern phrases; reward absence
      local ai_hits
      ai_hits="$(grep -ciE "let's (explore|dive|look)|it's (important|worth|crucial)|in (conclusion|summary)|as (we|you) (can see|know)|furthermore|moreover|in order to|utilize|leverage" "$draft_file" 2>/dev/null || true)"
      ai_hits="${ai_hits:-0}"
      if   [[ "$ai_hits" -eq 0 ]]; then score=5; rationale="No AI-pattern phrases detected; prose reads naturally."
      elif [[ "$ai_hits" -eq 1 ]]; then score=4; rationale="One AI-pattern phrase detected; minor naturalness cost."
      elif [[ "$ai_hits" -le 3 ]]; then score=3; rationale="$ai_hits AI-pattern phrases detected; moderate impact."
      elif [[ "$ai_hits" -le 5 ]]; then score=2; rationale="$ai_hits AI-pattern phrases; clearly affects readability."
      else score=1; rationale="$ai_hits+ AI-pattern phrases; heavy stylistic tell."; fi
      ;;
    structure)
      # Hook: first sentence should be short and punchy (<= 12 words)
      # Close: last non-empty line should be >= 5 words (substantial)
      local first_line_words last_line_words
      first_line_words="$(head -1 "$draft_file" | wc -w | tr -d ' ')"
      last_line_words="$(grep -v '^[[:space:]]*$' "$draft_file" | tail -1 | wc -w | tr -d ' ')"
      local struct_score=3
      [[ "$first_line_words" -le 12 && "$first_line_words" -ge 3 ]] && (( struct_score++ )) || true
      [[ "$last_line_words" -ge 5 ]] && (( struct_score++ )) || true
      [[ "$struct_score" -gt 5 ]] && struct_score=5
      score="$struct_score"
      rationale="Hook: $first_line_words words (optimal ≤12, ≥3). Close: $last_line_words words."
      ;;
    voice_fit)
      # Check absence of first-person plural and prescriptive imperatives
      local plural_we prescriptive
      plural_we="$(grep -ciE '\b(we|our|us)\b' "$draft_file" 2>/dev/null || true)"
      prescriptive="$(grep -ciE '\b(you should|you must|you need to|always|never use)\b' "$draft_file" 2>/dev/null || true)"
      plural_we="${plural_we:-0}"; prescriptive="${prescriptive:-0}"
      local vf_total=$(( plural_we + prescriptive ))
      if   [[ "$vf_total" -eq 0 ]]; then score=5; rationale="No first-person plural or prescriptive tone detected."
      elif [[ "$vf_total" -le 2 ]]; then score=4; rationale="Minimal voice violations ($vf_total instance(s))."
      elif [[ "$vf_total" -le 4 ]]; then score=3; rationale="Moderate voice violations ($vf_total instance(s))."
      else score=2; rationale="Multiple voice violations ($vf_total instance(s)); affects brand fit."; fi
      ;;
    factual_accuracy)
      # Presence of verifiable signals: numbers, year tokens, named entities
      local num_count year_count
      num_count="$(grep -oE '[0-9]+' "$draft_file" | wc -l | tr -d ' ')"
      year_count="$(grep -oE '20[0-9]{2}' "$draft_file" | wc -l | tr -d ' ')"
      local fact_total=$(( num_count + year_count * 2 ))
      if   [[ "$fact_total" -ge 6 ]]; then score=5; rationale="Strong factual signals: $num_count numeric tokens, $year_count year references."
      elif [[ "$fact_total" -ge 3 ]]; then score=4; rationale="Good factual grounding ($fact_total signal(s))."
      elif [[ "$fact_total" -ge 1 ]]; then score=3; rationale="Some factual signals ($fact_total)."
      else score=2; rationale="No verifiable numeric or temporal references found."; fi
      ;;
    ai_pattern_removal)
      # Same as naturalness but framed as a removal check
      local ai_hits
      ai_hits="$(grep -ciE "let's (explore|dive|look)|it's (important|worth|crucial)|in (conclusion|summary)|as (we|you) (can see|know)|furthermore|moreover|in order to|utilize|leverage" "$draft_file" 2>/dev/null || true)"
      ai_hits="${ai_hits:-0}"
      if   [[ "$ai_hits" -eq 0 ]]; then score=5; rationale="Zero AI-pattern phrases found; removal successful."
      elif [[ "$ai_hits" -eq 1 ]]; then score=4; rationale="One residual AI-pattern phrase remains."
      elif [[ "$ai_hits" -le 3 ]]; then score=3; rationale="$ai_hits residual AI-pattern phrases."
      else score=2; rationale="$ai_hits AI-pattern phrases not removed."; fi
      ;;
    platform_compliance)
      # Word count within typical platform limits (Telegram ~200, LinkedIn ~3000)
      if   [[ "$word_count" -le 250 ]]; then score=5; rationale="Word count ($word_count) within standard platform limits."
      elif [[ "$word_count" -le 500 ]]; then score=4; rationale="Word count ($word_count) within extended platform limits."
      elif [[ "$word_count" -le 1000 ]]; then score=3; rationale="Word count ($word_count) at upper range for short-form platforms."
      else score=2; rationale="Word count ($word_count) exceeds typical short-form platform limits."; fi
      ;;
    hook_strength)
      # First sentence should be concise and non-generic
      local first_line first_word first_len
      first_line="$(head -1 "$draft_file")"
      first_word="$(printf '%s\n' "$first_line" | awk '{print tolower($1)}')"
      first_len="$(printf '%s\n' "$first_line" | wc -w | tr -d ' ')"
      # Generic openers penalised
      local generic=0
      case "$first_word" in
        the|a|an|in|it|this|that|when|many|most|some) generic=1 ;;
        *) generic=0 ;;
      esac
      if   [[ "$first_len" -le 8 && "$generic" -eq 0 ]]; then score=5; rationale="Punchy hook ($first_len words), non-generic opening word."
      elif [[ "$first_len" -le 12 && "$generic" -eq 0 ]]; then score=4; rationale="Good hook ($first_len words), non-generic opening."
      elif [[ "$first_len" -le 15 ]]; then score=3; rationale="Adequate hook ($first_len words)."
      else score=2; rationale="Hook is long ($first_len words) or uses generic opener."; fi
      ;;
    link_validity)
      # Count URL tokens as a proxy for link presence
      local url_count
      url_count="$(grep -oE 'https?://[^[:space:]]+' "$draft_file" | wc -l | tr -d ' ')"
      if   [[ "$url_count" -ge 1 ]]; then score=4; rationale="$url_count URL token(s) present (validity requires live check)."
      else score=3; rationale="No URL tokens found (may be intentional for format)."; fi
      ;;
    length_fit)
      # Target 150-200 words; score by proximity
      if   [[ "$word_count" -ge 140 && "$word_count" -le 220 ]]; then score=5; rationale="Word count $word_count within target range (140-220)."
      elif [[ "$word_count" -ge 100 && "$word_count" -le 280 ]]; then score=4; rationale="Word count $word_count close to target range."
      elif [[ "$word_count" -ge 60  && "$word_count" -le 350 ]]; then score=3; rationale="Word count $word_count outside but near target range."
      elif [[ "$word_count" -lt 60 ]]; then score=2; rationale="Word count $word_count below minimum useful length."
      else score=2; rationale="Word count $word_count significantly exceeds target."; fi
      ;;
    *)
      # Unknown criterion: neutral score with explanation
      score=3
      rationale="Criterion '${crit_id}' has no dedicated signal function; neutral score assigned. Description: ${crit_desc}"
      ;;
  esac

  printf '%s\t%d\t%s\n' "$crit_id" "$score" "$rationale"
}

# ---------------------------------------------------------------------------
# Branch on judge mode
# ---------------------------------------------------------------------------
TEST_MODE="${DR_JUDGE_TEST_MODE:-0}"

# Temp file for scores
SCORES_FILE="$(mktemp)"
# shellcheck disable=SC2064
trap "rm -f '$SCORES_FILE'" EXIT

if [[ "$TEST_MODE" == "1" ]]; then
  # -------------------------------------------------------------------------
  # TEST-MODE PATH: deterministic word-count proxy (bats/CI only)
  # -------------------------------------------------------------------------
  for slot in "${OK_SLOTS[@]}"; do
    score="$(_test_mode_score "$RUN_DIR/draft-${slot}.md")"
    printf '%s\ttest_composite\t%s\tTest-mode fixture: word_count*2+unique_count proxy\n' \
      "$slot" "$score" >> "$SCORES_FILE"
  done

  # Find winner by composite test score (column 3)
  WINNER=""
  WINNER_SCORE=0
  for slot in "${OK_SLOTS[@]}"; do
    s="$(awk -v sl="$slot" -F'\t' '$1==sl && $2=="test_composite"{print $3}' "$SCORES_FILE")"
    s="${s:-0}"
    if [[ "$s" -gt "$WINNER_SCORE" ]]; then
      WINNER_SCORE="$s"
      WINNER="$slot"
    fi
  done
  [[ -z "$WINNER" ]] && WINNER="${OK_SLOTS[0]}"

  DECISION="$RUN_DIR/judge-decision.md"
  {
    printf '# Judge Decision\n\n'
    printf '> **NOTE: DR_JUDGE_TEST_MODE=1 — this output uses the word-count proxy test\n'
    printf '> fixture, NOT the production per-criterion judge. Do not use in production.**\n\n'
    printf '**Stage:** %s\n\n' "${STAGE:-write}"
    printf '**Drafts evaluated:** %d of %d vendors\n\n' "$DRAFT_COUNT" "$TOTAL_IN_LOG"
    if [[ "$DEGRADED" -eq 1 ]]; then
      printf '**degradation_note:** One or more vendors were unavailable; judgment\n'
      printf 'proceeded in 2-of-N degraded mode with the available drafts.\n\n'
    fi

    printf '## Score Matrix (test-mode fixture)\n\n'
    printf '| Vendor Slot | Composite Score (proxy) | Word Count | Notes |\n'
    printf '%s\n' '|-------------|-------------------------|------------|-------|'
    for slot in "${OK_SLOTS[@]}"; do
      draft="$RUN_DIR/draft-${slot}.md"
      wc_val="$(wc -w < "$draft" | tr -d ' ')"
      s="$(awk -v sl="$slot" -F'\t' '$1==sl && $2=="test_composite"{print $3}' "$SCORES_FILE")"
      winner_mark=""
      [[ "$slot" == "$WINNER" ]] && winner_mark=" **WINNER**"
      printf '| %s | %s | %s |%s |\n' "$slot" "$s" "$wc_val" "$winner_mark"
    done
    printf '\n'

    printf '## Rationale\n\n'
    printf 'Test-mode fixture selected slot **%s** (composite proxy score: %d).\n\n' \
      "$WINNER" "$WINNER_SCORE"
    printf 'In production runs (no DR_JUDGE_TEST_MODE flag), the per-criterion judge\n'
    printf 'scores each draft 1-5 against every named criterion with written rationale.\n\n'

    printf '## Traceability\n\n'
    printf '| Field | Value |\n'
    printf '%s\n' '|-------|-------|'
    printf '| selected_slot | %s |\n' "$WINNER"
    printf '| winner_score | %d |\n' "$WINNER_SCORE"
    printf '| judge_mode | test_fixture (word_count_proxy) |\n'
    printf '| drafts_evaluated | %d |\n' "$DRAFT_COUNT"
    printf '| run_log | run-log.jsonl |\n'
    printf '| criteria_file | %s |\n' "$(basename "$CRITERIA")"
  } > "$DECISION"

else
  # -------------------------------------------------------------------------
  # PRODUCTION PATH: per-criterion judgement
  #
  # Score each draft against each criterion. Build a draft×criterion matrix.
  # Winner = highest weighted sum of per-criterion scores.
  # -------------------------------------------------------------------------

  # Per-criterion scores: SLOT<TAB>CRIT_ID<TAB>SCORE<TAB>RATIONALE
  for slot in "${OK_SLOTS[@]}"; do
    draft_file="$RUN_DIR/draft-${slot}.md"
    for i in "${!CRIT_IDS[@]}"; do
      crit_id="${CRIT_IDS[$i]}"
      crit_desc="${CRIT_DESCS[$i]}"
      row="$(_per_criterion_score "$draft_file" "$crit_id" "$crit_desc")"
      printf '%s\t%s\n' "$slot" "$row" >> "$SCORES_FILE"
    done
  done

  # Compute weighted sum per slot
  WEIGHTED_SUMS_FILE="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$SCORES_FILE' '$WEIGHTED_SUMS_FILE'" EXIT

  for slot in "${OK_SLOTS[@]}"; do
    local_sum=0
    for i in "${!CRIT_IDS[@]}"; do
      cid="${CRIT_IDS[$i]}"
      wt="${CRIT_WEIGHTS[$i]}"
      raw_score="$(awk -v sl="$slot" -v ci="$cid" -F'\t' '$1==sl && $2==ci{print $3}' "$SCORES_FILE")"
      raw_score="${raw_score:-3}"
      local_sum=$(( local_sum + raw_score * wt ))
    done
    printf '%s\t%d\n' "$slot" "$local_sum" >> "$WEIGHTED_SUMS_FILE"
  done

  # Find winner (highest weighted sum; tiebreak: first in order)
  WINNER=""
  WINNER_SCORE=0
  for slot in "${OK_SLOTS[@]}"; do
    s="$(awk -v sl="$slot" -F'\t' '$1==sl{print $2}' "$WEIGHTED_SUMS_FILE")"
    s="${s:-0}"
    if [[ "$s" -gt "$WINNER_SCORE" ]]; then
      WINNER_SCORE="$s"
      WINNER="$slot"
    fi
  done
  [[ -z "$WINNER" ]] && WINNER="${OK_SLOTS[0]}"

  # Write judge-decision.md with full per-criterion matrix
  DECISION="$RUN_DIR/judge-decision.md"
  {
    printf '# Judge Decision\n\n'
    printf '**Judge mode:** per-criterion (production)\n\n'
    printf '**Stage:** %s\n\n' "${STAGE:-write}"
    printf '**Drafts evaluated:** %d of %d vendors\n\n' "$DRAFT_COUNT" "$TOTAL_IN_LOG"

    if [[ "$DEGRADED" -eq 1 ]]; then
      printf '**degradation_note:** One or more vendors were unavailable; judgment\n'
      printf 'proceeded in 2-of-N degraded mode with the available drafts.\n\n'
    fi

    printf '## Per-Criterion Score Matrix\n\n'
    # Build header
    printf '| Criterion (weight) |'
    for slot in "${OK_SLOTS[@]}"; do
      printf ' Slot %s |' "$slot"
    done
    printf '\n'
    printf '%s' '|--------------------|'
    for slot in "${OK_SLOTS[@]}"; do
      printf '%s' '---------|'
    done
    printf '\n'

    # One row per criterion
    for i in "${!CRIT_IDS[@]}"; do
      cid="${CRIT_IDS[$i]}"
      wt="${CRIT_WEIGHTS[$i]}"
      printf '| **%s** (w=%s) |' "$cid" "$wt"
      for slot in "${OK_SLOTS[@]}"; do
        sc="$(awk -v sl="$slot" -v ci="$cid" -F'\t' '$1==sl && $2==ci{print $3}' "$SCORES_FILE")"
        sc="${sc:-3}"
        printf ' %s/5 |' "$sc"
      done
      printf '\n'
    done

    printf '| **Weighted Total** |'
    for slot in "${OK_SLOTS[@]}"; do
      ws="$(awk -v sl="$slot" -F'\t' '$1==sl{print $2}' "$WEIGHTED_SUMS_FILE")"
      winner_mark=""
      [[ "$slot" == "$WINNER" ]] && winner_mark=" **W**"
      printf ' **%s**%s |' "${ws:-0}" "$winner_mark"
    done
    printf '\n\n'

    printf '## Per-Criterion Rationale\n\n'
    for i in "${!CRIT_IDS[@]}"; do
      cid="${CRIT_IDS[$i]}"
      wt="${CRIT_WEIGHTS[$i]}"
      printf '### %s (weight %s)\n\n' "$cid" "$wt"
      printf '> %s\n\n' "${CRIT_DESCS[$i]}"
      for slot in "${OK_SLOTS[@]}"; do
        sc="$(awk -v sl="$slot" -v ci="$cid" -F'\t' '$1==sl && $2==ci{print $3}' "$SCORES_FILE")"
        rat="$(awk -v sl="$slot" -v ci="$cid" -F'\t' '$1==sl && $2==ci{print $4}' "$SCORES_FILE")"
        sc="${sc:-3}"; rat="${rat:-No rationale recorded.}"
        printf '%s\n' "- **Slot ${slot}** — ${sc}/5: ${rat}"
      done
      printf '\n'
    done

    printf '## Winner Rationale\n\n'
    printf 'Selected draft from vendor slot **%s** (weighted score: %d).\n\n' \
      "$WINNER" "$WINNER_SCORE"
    printf 'The winner was determined by the weighted sum of per-criterion scores (1-5).\n'
    printf 'Each criterion contributes proportionally to its assigned weight.\n'
    printf 'The per-criterion rationale above traces exactly why each score was assigned.\n\n'

    # Grafted ideas note
    printf '### Grafted ideas from non-winning drafts\n\n'
    for slot in "${OK_SLOTS[@]}"; do
      [[ "$slot" == "$WINNER" ]] && continue
      printf '%s\n' "- Slot ${slot}: consider incorporating unique strengths identified in the per-criterion rationale above."
    done
    printf '\n'

    printf '## Traceability\n\n'
    printf '| Field | Value |\n'
    printf '%s\n' '|-------|-------|'
    printf '| selected_slot | %s |\n' "$WINNER"
    printf '| winner_weighted_score | %d |\n' "$WINNER_SCORE"
    printf '| judge_mode | per_criterion_production |\n'
    printf '| criteria_count | %d |\n' "${#CRIT_IDS[@]}"
    printf '| drafts_evaluated | %d |\n' "$DRAFT_COUNT"
    printf '| run_log | run-log.jsonl |\n'
    printf '| criteria_file | %s |\n' "$(basename "$CRITERIA")"

    rm -f "$WEIGHTED_SUMS_FILE"
  } > "$DECISION"
fi

# Copy winning draft to final.md
cp "$RUN_DIR/draft-${WINNER}.md" "$RUN_DIR/final.md"

if [[ "$TEST_MODE" == "1" ]]; then
  judge_mode="test_fixture"
else
  judge_mode="per_criterion_production"
fi
printf 'Judge complete: mode=%s winner=slot-%s final=%s/final.md\n' \
  "$judge_mode" "$WINNER" "$RUN_DIR"
exit 0
