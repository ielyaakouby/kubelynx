#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Print versions of tools KubeLynx uses. Portable: no GNU-only grep -P.

set -euo pipefail

CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

first_line_version() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        return 1
    fi
    local output
    output="$("$cmd" --version 2>&1 | head -n 1 || true)"
    # Keep the first dotted numeric token if present, otherwise the whole line.
    local token
    token="$(printf '%s\n' "$output" | awk '{
        for (i = 1; i <= NF; i++) {
            if ($i ~ /[0-9]+\.[0-9]+/) { print $i; exit }
        }
    }')"
    if [[ -n "$token" ]]; then
        printf '%s\n' "$token"
    else
        printf '%s\n' "$output"
    fi
}

print_one() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        printf "  %-16s %s\n" "$cmd" "$(first_line_version "$cmd")"
    else
        printf "  ${RED}%-16s not found${NC}\n" "$cmd"
    fi
}

echo -e "${CYAN}[INFO]${NC} Tool versions"
print_one bash
print_one kubectl
print_one fzf
print_one jq
print_one curl
print_one git
