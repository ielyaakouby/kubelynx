#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Remove KubeLynx-owned files only. Idempotent. Never uses sudo.
# Never deletes the current working clone unless it is the install directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

DEST="$(kubelynx::install_dir)"
LINK="$(kubelynx::bin_link)"
LEGACY_LINK="$(kubelynx::legacy_bin_link)"
LEGACY_XDG="$(kubelynx::legacy_install_dir)"
LEGACY_HOME="$(kubelynx::legacy_home_dir)"
REMOVED=0

remove_link() {
    local path="$1"
    if [[ -L "$path" ]]; then
        local target
        target="$(readlink "$path" || true)"
        case "$target" in
            */kubelynx.sh | */kubediag.sh)
                rm -f "$path"
                echo "[OK] Removed symlink $path"
                REMOVED=1
                ;;
            *)
                echo "[WARN] $path is a symlink but does not point at kubelynx.sh; leaving it in place."
                ;;
        esac
    elif [[ -e "$path" ]]; then
        echo "[WARN] $path exists and is not a symlink; leaving it in place."
    fi
}

remove_dir_if_safe() {
    local dir="$1"
    local label="${2:-install directory}"
    if [[ ! -e "$dir" ]]; then
        return 0
    fi
    if ! kubelynx::is_safe_install_dir "$dir"; then
        echo "[ERROR] Refusing to delete unsafe path: $dir" >&2
        return 1
    fi
    rm -rf -- "$dir"
    echo "[OK] Removed $label: $dir"
    REMOVED=1
}

echo "[INFO] Uninstalling KubeLynx..."

remove_link "$LINK"
remove_link "$LEGACY_LINK"

# Development installs keep the clone; only the symlink is removed.
# Copied installs live under the XDG data directory.
if [[ -d "$DEST" ]]; then
    mode="$(kubelynx::meta_value "$(kubelynx::meta_file "$DEST")" MODE || true)"
    if [[ "$mode" == "dev" ]]; then
        echo "[INFO] Development install detected; clone at $DEST was not deleted."
        rm -f "$DEST/.kubelynx-meta" "$DEST/.kubediag-meta"
    else
        remove_dir_if_safe "$DEST" "install directory"
    fi
fi

# Previous Kubediag default locations (pre-rename). Only those exact layouts.
if [[ -d "$LEGACY_XDG" && "$LEGACY_XDG" != "$DEST" ]]; then
    if kubelynx::is_safe_install_dir "$LEGACY_XDG"; then
        rm -rf -- "$LEGACY_XDG"
        echo "[OK] Removed legacy Kubediag directory: $LEGACY_XDG"
        REMOVED=1
    fi
fi

if [[ -d "$LEGACY_HOME" ]]; then
    if kubelynx::is_safe_install_dir "$LEGACY_HOME" || [[ "$LEGACY_HOME" == "${HOME}/.kubediag/kubediag" ]]; then
        rm -rf -- "$LEGACY_HOME"
        echo "[OK] Removed legacy directory: $LEGACY_HOME"
        REMOVED=1
        rmdir "${HOME}/.kubediag" 2>/dev/null || true
    fi
fi

if [[ "$REMOVED" -eq 0 ]]; then
    echo "[INFO] KubeLynx was not installed. Nothing to uninstall."
else
    echo "[OK] Uninstall complete."
fi

exit 0
