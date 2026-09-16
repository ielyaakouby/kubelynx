#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Minimal local smoke walkthrough (no cluster required).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "KubeLynx demo"
echo
./bin/kubelynx.sh --version
echo
./bin/kubelynx.sh --help
echo
echo "Interactive mode: ./bin/kubelynx.sh"
echo "Install:          ./installer/install.sh"
