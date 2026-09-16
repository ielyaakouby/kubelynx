#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Build platform-neutral release archives from the repository.
# Usage: scripts/package-release.sh [output-dir]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-${ROOT}/dist}"

version=""
if [[ -f "${ROOT}/VERSION" ]]; then
    version="$(tr -d '[:space:]' <"${ROOT}/VERSION")"
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.]+)?$ ]]; then
    echo "[ERROR] VERSION is missing or malformed: ${ROOT}/VERSION" >&2
    exit 1
fi

tag="v${version}"
stage="${OUT_DIR}/kubelynx-${tag}"
rm -rf "$stage"
mkdir -p "$stage"

include_items=(bin config installer src LICENSE NOTICE README.md VERSION CHANGELOG.md)
for item in "${include_items[@]}"; do
    if [[ -e "${ROOT}/${item}" ]]; then
        cp -a "${ROOT}/${item}" "${stage}/${item}"
    else
        echo "[ERROR] Required path missing from repository: $item" >&2
        exit 1
    fi
done

# Drop development-only installer helpers that are not required at runtime? Keep
# the full installer/ tree so users can install from the archive.

find "$stage" -type f \( -name '*.swp' -o -name '*.tmp' -o -name '.DS_Store' \) -delete
find "$stage" -type d -name '.cache' -exec rm -rf {} + 2>/dev/null || true

mkdir -p "$OUT_DIR"
(
    cd "$OUT_DIR"
    tar -czf "kubelynx-${tag}.tar.gz" "kubelynx-${tag}"
    if command -v zip >/dev/null 2>&1; then
        zip -qr "kubelynx-${tag}.zip" "kubelynx-${tag}"
    else
        echo "[ERROR] zip is required to build the .zip artifact." >&2
        exit 1
    fi
)

checksum_tool() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$@"
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$@"
    else
        echo "[ERROR] Neither sha256sum nor shasum is available." >&2
        return 1
    fi
}

(
    cd "$OUT_DIR"
    checksum_tool "kubelynx-${tag}.tar.gz" "kubelynx-${tag}.zip" >SHA256SUMS
)

echo "[OK] Wrote:"
echo "     ${OUT_DIR}/kubelynx-${tag}.tar.gz"
echo "     ${OUT_DIR}/kubelynx-${tag}.zip"
echo "     ${OUT_DIR}/SHA256SUMS"
