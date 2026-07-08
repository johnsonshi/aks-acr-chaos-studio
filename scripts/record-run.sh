#!/usr/bin/env bash
# Write a per-run summary.md (hypothesis + probes + SLIs + a verdict checkbox) into RUN_DIR.
set -euo pipefail
EXP="${EXP:?set EXP}"
RUN_DIR="${RUN_DIR:?set RUN_DIR}"
HOLD_MIN="${HOLD_MIN:-?}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# key = the experiment code after the prefix, e.g. acrchaos-a1-nsg-block-acr -> a1
KEY=$(echo "$EXP" | sed -E 's/^[^-]+-([a-z0-9]+).*/\1/')
HYP=$(awk -F'|' -v k="$KEY" '$1==k{print $2}' "${ROOT}/experiments/hypotheses.txt")
EXPECT=$(awk -F'|' -v k="$KEY" '$1==k{print $3}' "${ROOT}/experiments/hypotheses.txt")
[ -z "$HYP" ] && HYP="(no hypothesis on file for '$KEY' — see README §5)"

mkdir -p "$RUN_DIR"
cat > "${RUN_DIR}/summary.md" <<EOF
# ${EXP} — run summary

- **Recorded:** $(date -u +%Y-%m-%dT%H:%M:%SZ)  (hold: ${HOLD_MIN}m)
- **Hypothesis:** ${HYP}
- **Expected signal:** ${EXPECT}

## Artifacts in this run
- Reachability: \`probe-before.txt\`, \`probe-during.txt\` (az aks check-acr / az acr check-health)
- SLIs (Log Analytics): \`sli-pull-success.txt\`, \`auth-failures.txt\`, \`throttling-429.txt\`

## Verdict
- Result: **[ ] PASS   [ ] FAIL**
- Did the observed behavior match the hypothesis + expected signal? Notes:
-
EOF
echo ">> wrote ${RUN_DIR}/summary.md"
