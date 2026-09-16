#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Scan the repository for high-confidence secret patterns. Development helper.

set -euo pipefail

echo "[INFO] Scanning for potential secrets..."

patterns=(
    'AKIA[0-9A-Z]{16}'
    '-----BEGIN[[:space:]]+PRIVATE[[:space:]]+KEY-----'
    'ghp_[A-Za-z0-9]{36}'
)

found=false
while IFS= read -r -d '' file; do
    for pattern in "${patterns[@]}"; do
        if grep -E -q -- "$pattern" "$file"; then
            echo "[WARN] Possible secret in: $file"
            grep -En -- "$pattern" "$file" | sed 's/^/    > /' || true
            found=true
        fi
    done
done < <(find . -type f \
    -not -path './.git/*' \
    -not -path './dist/*' \
    -not -name '*.md' \
    -print0)

if [[ "$found" == true ]]; then
    echo
    echo "[FAIL] Potential secrets found. Review before publishing."
    exit 1
fi

echo "[OK] No high-confidence secret patterns detected."
