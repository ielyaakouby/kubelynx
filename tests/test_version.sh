#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

out="$(./bin/kubelynx.sh --version)"
expected="KubeLynx v$(tr -d '[:space:]' <VERSION)"
[[ "$out" == "$expected" ]] || fail "expected '$expected', got '$out'"

out_v="$(./bin/kubelynx.sh -v)"
[[ "$out_v" == "$expected" ]] || fail "-v output mismatch"

echo "version output: $out"
