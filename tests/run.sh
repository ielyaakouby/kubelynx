#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Lightweight test runner. Does not require a Kubernetes cluster.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

failures=0
ran=0

run_test() {
    local file="$1"
    ran=$((ran + 1))
    printf '==> %s\n' "$file"
    if bash "$file"; then
        printf '    PASS\n'
    else
        printf '    FAIL\n'
        failures=$((failures + 1))
    fi
}

shopt -s nullglob
for t in tests/test_*.sh; do
    run_test "$t"
done

echo
if [[ "$failures" -ne 0 ]]; then
    echo "$failures of $ran tests failed"
    exit 1
fi

echo "$ran tests passed"
exit 0
