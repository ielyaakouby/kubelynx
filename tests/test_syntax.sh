#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

status=0
while IFS= read -r -d '' file; do
    if ! bash -n "$file"; then
        echo "syntax error: $file" >&2
        status=1
    fi
done < <(find . -type f -name '*.sh' -not -path './.git/*' -not -path './dist/*' -print0 | sort -z)

[[ "$status" -eq 0 ]] || fail "one or more scripts failed bash -n"
