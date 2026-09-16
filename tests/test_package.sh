#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

work="$(mktemp -d "${TMPDIR:-/tmp}/kubelynx-pkg.XXXXXX")"
trap 'rm -rf "$work"' EXIT

bash scripts/package-release.sh "$work"
version="$(tr -d '[:space:]' <VERSION)"
tag="v${version}"

[[ -f "${work}/kubelynx-${tag}.tar.gz" ]] || fail "missing tar.gz"
[[ -f "${work}/SHA256SUMS" ]] || fail "missing SHA256SUMS"

# Must not package development-only trees.
if tar -tzf "${work}/kubelynx-${tag}.tar.gz" | grep -E '/(\.git|\.github|tests)(/|$)'; then
    fail "archive contains development-only paths"
fi

extract="${work}/x"
mkdir "$extract"
tar -xzf "${work}/kubelynx-${tag}.tar.gz" -C "$extract"
"${extract}/kubelynx-${tag}/bin/kubelynx.sh" --version | grep -q "KubeLynx v${version}" || fail "archive CLI version mismatch"
if tar -tzf "${work}/kubelynx-${tag}.tar.gz" | grep -E '(^|/)bin/kubediag\.sh$|kubediag-v'; then
    fail "archive still contains a kubediag-named runtime path"
fi
