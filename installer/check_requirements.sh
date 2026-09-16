#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Check KubeLynx prerequisites.
# Runtime tools are required to use the CLI.
# Optional tools enable extra features and are never fatal.

set -euo pipefail

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

missing_required=0
missing_optional=0

check_cmd() {
    local cmd="$1"
    local kind="$2"
    local note="${3:-}"
    if command -v "$cmd" >/dev/null 2>&1; then
        printf "${GREEN}[OK]${NC}   %-16s %s\n" "$cmd" "${note}"
        return 0
    fi
    if [[ "$kind" == "required" ]]; then
        printf "${RED}[FAIL]${NC} %-16s missing (required)\n" "$cmd"
        missing_required=1
    else
        printf "${YELLOW}[WARN]${NC} %-16s missing (optional%s)\n" "$cmd" "${note:+: ${note}}"
        missing_optional=1
    fi
    return 1
}

echo "KubeLynx prerequisite check"
echo

echo "Runtime requirements"
check_cmd bash "required"
check_cmd kubectl "required"
check_cmd fzf "required"
check_cmd jq "required"
echo

echo "Optional runtime features"
check_cmd curl "optional" "connectivity checks and AI providers"
check_cmd gnome-terminal "optional" "open some actions in a new window"
echo

echo "Installation and update"
check_cmd git "optional" "clone-based install and git updates"
check_cmd tar "optional" "release archive extraction"
echo

if [[ "$missing_required" -ne 0 ]]; then
    printf '%b[FAIL]%b Missing required commands. Install them and re-run this check.\n' "$RED" "$NC"
    exit 1
fi

if [[ "$missing_optional" -ne 0 ]]; then
    printf '%b[INFO]%b Optional tools are missing. KubeLynx will still run; related features will be skipped.\n' "$YELLOW" "$NC"
else
    printf '%b[OK]%b   All required and optional commands are available.\n' "$GREEN" "$NC"
fi

exit 0
