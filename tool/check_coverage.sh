#!/usr/bin/env bash
set -euo pipefail

LCOV_FILE="coverage/lcov.info"
BASELINE_FILE="coverage_baseline.txt"
TOLERANCE="${COVERAGE_TOLERANCE:-0.0}"

if [   !   -f  "$LCOV_FILE"   ]; then
    echo "Coverage file not found at $LCOV_FILE. Did 'flutter test --coverage' run?"
    exit 1
fi

if [ ! -f "$BASELINE_FILE" ]; then
    echo "Basline file not found at $BASELINE_FILE."
    exit 1
fi

BASELINE=$(tr -d '[:space:]' < "$BASELINE_FILE")

read -r LF LH <<EOF_VALS
$(awk -F: '
    /^LF:/ { lf += $2  }
    /^LH:/ { lh += $2  }
    END { print lf, lh }
' "$LCOV_FILE")
EOF_VALS

if [ -z "$LF" ] || [ "$LF" -eq 0 ]; then
    echo "No coverag data found in $LCOV_FILE"
    exit 1
fi

CURRENT=$(awk -v lh="$LH" -v lf="$LF" 'BEGIN { printf "%.2f", (lh/lf)*100 }')

echo "Current coverage: ${CURRENT}%"
echo "Baseline coverage: ${BASELINE}%"

PASS=$(awk -v cur="$CURRENT" -v base="$BASELINE" -v tol="$TOLERANCE" \
    'BEGIN { print (cur >= (base - tol)) ? "1" : "0" }')

if [ "$PASS" -eq 0 ]; then
    echo ""
    echo "Coverage regression detected: ${CURRENT}% is below the baseline of ${BASELINE}%."
    echo "Add tests to restore coverage, or if the drop is intentional and justified,"
    echo "update coverage_baseline.txt in this PR and explain why in the description."
    exit 1
fi

echo "Coverage check passed."

if awk -v cur="$CURRENT" -v base="$BASELINE" 'BEGIN { exit !(cur > base) }'; then
    echo "Coverage improved (${CURRENT}% > ${BASELINE}%)."
    echo "Consider bumping coverage_baseline.txt to lock in the gain."
fi