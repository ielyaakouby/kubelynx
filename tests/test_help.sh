#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

out="$(./bin/kubelynx.sh --help)"
printf '%s\n' "$out" | grep -q 'Usage:' || fail "help missing Usage"
printf '%s\n' "$out" | grep -q -- '--version' || fail "help missing --version"
printf '%s\n' "$out" | grep -q -- '--help' || fail "help missing --help"
printf '%s\n' "$out" | grep -q 'KubeLynx' || fail "help missing KubeLynx brand"
printf '%s\n' "$out" | grep -q 'kubelynx' || fail "help missing kubelynx command"
if printf '%s\n' "$out" | grep -qi 'kubediag'; then
    fail "help still mentions kubediag"
fi

out_h="$(./bin/kubelynx.sh -h)"
printf '%s\n' "$out_h" | grep -q 'Usage:' || fail "-h missing Usage"
