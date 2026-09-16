#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Load modules without contacting a Kubernetes cluster.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

# Isolate kubeconfig so a developer cluster cannot be touched.
export KUBECONFIG="${ROOT}/tests/empty.kubeconfig"
mkdir -p "$(dirname "$KUBECONFIG")"
# Intentionally invalid kubeconfig path — module loading must not call kubectl.
rm -f "$KUBECONFIG"

if ! ./bin/kubelynx.sh ok; then
    fail "library mode (ok) failed while loading modules"
fi

# Missing optional tools must not crash --help / --version.
PATH="/usr/bin:/bin" ./bin/kubelynx.sh --help >/dev/null || fail "help failed with a stripped PATH"
PATH="/usr/bin:/bin" ./bin/kubelynx.sh --version >/dev/null || fail "version failed with a stripped PATH"
