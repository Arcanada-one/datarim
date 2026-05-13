#!/usr/bin/env bats
# dr-init-topic-overlap-fp-budget.bats — AC-3 regression spec.
# Sweeps 30 orthogonal probes against a 35-item fixture (30 unrelated + 5 known
# overlap targets) and asserts FP rate <10% (≤3 spurious matches) while TP rate
# captures ≥4 of 5 known-overlap items.

SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/check-topic-overlap.py"
FIXTURE="$BATS_TEST_DIRNAME/fixtures/topic-overlap/backlog-30-orthogonal.md"

@test "FP budget: <=3 false positives on 30 orthogonal probes" {
    fp_count=0
    for desc in \
        "ancient Roman aqueduct engineering principles" \
        "molecular gastronomy spherification technique" \
        "Baroque counterpoint voice leading rules" \
        "marine coral reef bleaching recovery patterns" \
        "impressionist oil painting pigment decomposition" \
        "quantum entanglement photon polarization experiments" \
        "Meissner effect superconductor magnetic levitation" \
        "Byzantine mosaic tesserae gold leaf restoration" \
        "alpine glacier moraine sediment deposition rates" \
        "jazz syncopation rhythmic displacement analysis" \
        "CRISPR Cas9 gene editing off-target mitigation" \
        "Gothic rib vault flying buttress load distribution" \
        "deep sea hydrothermal vent chemosynthesis biology" \
        "Ottoman miniature painting brush stroke taxonomy" \
        "phonetic vowel shift historical linguistics dataset" \
        "temperate rainforest mycorrhizal network mapping" \
        "Egyptian hieroglyphic determinative semantic classes" \
        "fluid dynamics turbulence vortex shedding cylinder" \
        "Kabuki theater mie pose dramatic gesture lexicon" \
        "paleolithic cave painting ochre pigment sourcing" \
        "stochastic calculus Ito lemma financial derivatives" \
        "Andean terraced agriculture irrigation hydrology" \
        "neuroplasticity synaptic pruning adolescent brain" \
        "Mughal garden charbagh quadripartite layout" \
        "aerodynamics swept wing compressibility effects" \
        "polyrhythm Sub-Saharan drum ensemble transcription" \
        "vulcanology pyroclastic flow deposit stratigraphy" \
        "Hellenistic bronze casting lost wax methodology" \
        "cryogenic nitrogen freezing tissue sample protocol" \
        "ethnobotanical shamanic ritual psychoactive flora"; do
        run python3 "$SCRIPT" --task-description - --backlog "$FIXTURE" <<< "$desc"
        [ "$status" -eq 0 ]
        if [ -n "$output" ]; then
            fp_count=$((fp_count + 1))
        fi
    done
    [ "$fp_count" -le 3 ]
}

@test "TP budget: >=4 true positives on 5 known-overlap probes" {
    tp_count=0
    declare -a probes=(
        "fb publishing helper for MCP playwright sandbox:TPB-0001"
        "JWKS rotation cadence and key audit policy update:TPB-0002"
        "middleware output guard and observability pipeline:TPB-0003"
        "Stripe webhook billing idempotency retry handling:TPB-0004"
        "postgres cold storage write ahead log archival policy:TPB-0005"
    )
    for entry in "${probes[@]}"; do
        IFS=: read -r desc tid <<< "$entry"
        run python3 "$SCRIPT" --task-description - --backlog "$FIXTURE" <<< "$desc"
        [ "$status" -eq 0 ]
        if [[ "$output" == *"$tid"* ]]; then
            tp_count=$((tp_count + 1))
        fi
    done
    [ "$tp_count" -ge 4 ]
}
