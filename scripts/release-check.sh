#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Verify release prerequisites: VERSION, license, and packaging contents.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

version="$(tr -d '[:space:]' <VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.]+)?$ ]] || fail "VERSION is malformed: $version"

[[ -f LICENSE ]] || fail "LICENSE is missing"
grep -q 'Apache License' LICENSE || fail "LICENSE does not look like Apache License 2.0"

[[ -f NOTICE ]] || fail "NOTICE is missing"
grep -q 'Copyright 2026 Ismail Elyaakouby' NOTICE || fail "NOTICE is missing the copyright line"

mit_hits="$(grep -R --exclude-dir=.git --exclude='release-check.sh' -n 'SPDX-License-Identifier: MIT' . || true)"
if [[ -n "$mit_hits" ]]; then
    printf '%s\n' "$mit_hits"
    fail "Found leftover MIT SPDX identifiers"
fi

if grep -n 'readonly KUBELYNX_VERSION=' bin/kubelynx.sh; then
    fail "bin/kubelynx.sh still hardcodes KUBELYNX_VERSION"
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/kubelynx-release-check.XXXXXX")"
trap 'rm -rf "$work"' EXIT

bash scripts/package-release.sh "$work"

tag="v${version}"
[[ -f "${work}/kubelynx-${tag}.tar.gz" ]] || fail "tar.gz artifact missing"
[[ -f "${work}/kubelynx-${tag}.zip" ]] || fail "zip artifact missing"
[[ -f "${work}/SHA256SUMS" ]] || fail "SHA256SUMS missing"

extract="${work}/extract"
mkdir -p "$extract"
tar -xzf "${work}/kubelynx-${tag}.tar.gz" -C "$extract"
tree="${extract}/kubelynx-${tag}"
[[ -d "$tree" ]] || fail "Archive top-level directory should be kubelynx-${tag}"
[[ -f "${tree}/bin/kubelynx.sh" ]] || fail "Archive missing bin/kubelynx.sh"
[[ -f "${tree}/VERSION" ]] || fail "Archive missing VERSION"
[[ -f "${tree}/LICENSE" ]] || fail "Archive missing LICENSE"
[[ ! -d "${tree}/.git" ]] || fail "Archive must not contain .git"
[[ ! -d "${tree}/.github" ]] || fail "Archive must not contain .github"
[[ ! -d "${tree}/tests" ]] || fail "Archive must not contain tests"

if command -v sha256sum >/dev/null 2>&1; then
    (cd "$work" && sha256sum -c SHA256SUMS >/dev/null)
fi

echo "[OK] Release prerequisites look good for ${tag}"
