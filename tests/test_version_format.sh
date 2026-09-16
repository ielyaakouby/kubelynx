#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

version="$(tr -d '[:space:]' <VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.]+)?$ ]] || fail "VERSION '$version' is not semver"

# Malformed VERSION must be rejected without Git and without a hardcoded fallback.
work="$(mktemp -d "${TMPDIR:-/tmp}/kubelynx-version.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cp -a bin "$work/bin"
mkdir -p "$work/config" "$work/src/k8s"
printf 'not-a-version\n' >"$work/VERSION"
if "$work/bin/kubelynx.sh" --version >/dev/null 2>&1; then
    fail "malformed VERSION should cause --version to fail"
fi
malformed_out="$("$work/bin/kubelynx.sh" --version 2>&1 || true)"
printf '%s\n' "$malformed_out" | grep -q 'unknown' || fail "malformed VERSION should report unknown"

printf '   \n' >"$work/VERSION"
if "$work/bin/kubelynx.sh" --version >/dev/null 2>&1; then
    fail "empty VERSION should cause --version to fail"
fi
