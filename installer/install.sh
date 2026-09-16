#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Install KubeLynx into user-space.
#
# Default locations:
#   application : ${XDG_DATA_HOME:-$HOME/.local/share}/kubelynx
#   executable  : ${HOME}/.local/bin/kubelynx
#
# Usage:
#   ./installer/install.sh          # copy runtime files into the install dir
#   ./installer/install.sh --dev    # symlink this clone (development)
#
# Never requires sudo. Never edits shell rc files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
    cat <<'EOF'
Usage: install.sh [--dev] [--help]

  --dev    Development install: symlink this working tree instead of copying.
           The clone is not moved. Only ~/.local/bin/kubelynx is created.

Installation is always user-space and never uses sudo.

Application directory:
  ${XDG_DATA_HOME:-$HOME/.local/share}/kubelynx

Executable:
  ${HOME}/.local/bin/kubelynx
EOF
}

DEV_INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --dev) DEV_INSTALL=1 ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            usage >&2
            exit 1
            ;;
    esac
done

SRC="$(kubelynx::source_root)"
DEST="$(kubelynx::install_dir)"
BIN_DIR="$(kubelynx::bin_dir)"
LINK="$(kubelynx::bin_link)"

if ! kubelynx::is_runtime_tree "$SRC"; then
    echo "[ERROR] Cannot find a KubeLynx runtime tree at: $SRC" >&2
    exit 1
fi

echo "[INFO] Source:      $SRC"
echo "[INFO] Install dir: $DEST"
echo "[INFO] Executable:  $LINK"

mkdir -p "$BIN_DIR"
kubelynx::migrate_legacy_install "$DEST" "$SRC"

if [[ "$DEV_INSTALL" -eq 1 ]]; then
    ln -sfn "$SRC/bin/kubelynx.sh" "$LINK"
    chmod +x "$SRC/bin/kubelynx.sh"
    kubelynx::write_meta "$SRC" "dev" "$SRC"
    echo "[OK] Development install complete (symlink to this clone)."
else
    if [[ "$SRC" == "$DEST" ]]; then
        echo "[INFO] Already running from the install directory; skipping copy."
    else
        echo "[INFO] Copying runtime files..."
        mkdir -p "$DEST"
        kubelynx::copy_runtime "$SRC" "$DEST"
    fi
    chmod +x "$DEST/bin/kubelynx.sh"
    ln -sfn "$DEST/bin/kubelynx.sh" "$LINK"
    local_mode="$(kubelynx::detect_install_mode "$DEST")"
    kubelynx::write_meta "$DEST" "$local_mode" "$SRC"
    echo "[OK] KubeLynx installed to $DEST"
fi

kubelynx::print_path_hint "$BIN_DIR"
echo "[OK] Run: kubelynx"
exit 0
