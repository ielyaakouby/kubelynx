#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Run a command while showing a spinner. Avoids eval.

set -euo pipefail

# shellcheck source=utils.sh
source "$(dirname "$0")/utils.sh"

if [[ $# -lt 2 ]]; then
    echo "Usage: spinner-wrapper.sh <message> <command> [args...]" >&2
    exit 2
fi

msg="$1"
shift

show_spinner "$msg" &
spinner_pid=$!

set +e
"$@"
cmd_status=$?
set -e

stop_spinner "$spinner_pid" "$msg"

if [[ "$cmd_status" -ne 0 ]]; then
    echo "[FAIL] Command failed: $*"
    exit "$cmd_status"
fi
