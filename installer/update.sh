#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Update an existing KubeLynx installation.
# - Git / development installs: git pull on the tracked clone.
# - Release installs: download the latest GitHub Release archive.
# Never fast-forwards a release user onto unreleased main.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

DEST="$(kubelynx::install_dir)"
SRC_ROOT="$(kubelynx::source_root)"
LINK="$(kubelynx::bin_link)"

# Prefer the installed copy; fall back to this working tree (dev / in-place).
TARGET="$DEST"
MODE=""
if [[ -f "$(kubelynx::meta_file "$DEST")" ]]; then
    MODE="$(kubelynx::meta_value "$(kubelynx::meta_file "$DEST")" MODE || true)"
fi
if [[ "$MODE" == "dev" ]]; then
    TARGET="$(kubelynx::meta_value "$(kubelynx::meta_file "$DEST")" SOURCE || echo "$SRC_ROOT")"
elif [[ ! -d "$DEST" ]] && kubelynx::is_runtime_tree "$SRC_ROOT"; then
    TARGET="$SRC_ROOT"
    MODE="$(kubelynx::detect_install_mode "$TARGET")"
elif [[ -z "$MODE" && -d "$DEST" ]]; then
    MODE="$(kubelynx::detect_install_mode "$DEST")"
fi

if [[ ! -d "$TARGET" ]]; then
    echo "[ERROR] KubeLynx does not appear to be installed at $DEST" >&2
    echo "[INFO] Install from a release archive or clone, then run installer/install.sh" >&2
    exit 1
fi

update_git() {
    local repo="$1"
    if [[ ! -d "$repo/.git" ]]; then
        return 1
    fi
    if ! command -v git >/dev/null 2>&1; then
        echo "[ERROR] git is required to update a Git-based installation." >&2
        exit 1
    fi
    echo "[INFO] Updating Git installation at $repo"
    git -C "$repo" fetch --tags --quiet
    local branch
    branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
    git -C "$repo" pull --ff-only --quiet
    echo "[OK] Updated $repo (branch: $branch)"
}

update_release() {
    local dest="$1"
    if ! command -v curl >/dev/null 2>&1; then
        echo "[ERROR] curl is required to update a release installation." >&2
        exit 1
    fi
    local api latest_tag archive tmp work
    api="$(kubelynx::api_url)/releases/latest"
    echo "[INFO] Checking latest GitHub Release..."
    latest_tag="$(curl -fsSL "$api" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    if [[ -z "$latest_tag" ]]; then
        echo "[ERROR] Could not determine the latest release tag from GitHub." >&2
        echo "[INFO] Download the latest archive from $(kubelynx::repo_url)/releases/latest" >&2
        exit 1
    fi
    local current
    current="$(kubelynx::read_version_file "$dest/VERSION" || echo unknown)"
    echo "[INFO] Installed version: $current"
    echo "[INFO] Latest release:    $latest_tag"
    if [[ "v${current}" == "$latest_tag" ]]; then
        echo "[OK] Already up to date."
        return 0
    fi
    archive="$(kubelynx::repo_url)/releases/download/${latest_tag}/kubelynx-${latest_tag}.tar.gz"
    tmp="$(mktemp "${TMPDIR:-/tmp}/kubelynx-update.XXXXXX.tar.gz")"
    work="$(mktemp -d "${TMPDIR:-/tmp}/kubelynx-update.XXXXXX")"
    # Invoked via trap on EXIT; not a dead code path.
    # shellcheck disable=SC2317
    cleanup() {
        rm -f "$tmp"
        rm -rf "$work"
    }
    trap cleanup EXIT
    echo "[INFO] Downloading $archive"
    if ! curl -fsSL "$archive" -o "$tmp"; then
        echo "[ERROR] Failed to download $archive" >&2
        echo "[INFO] Update manually from $(kubelynx::repo_url)/releases/latest" >&2
        exit 1
    fi
    tar -xzf "$tmp" -C "$work"
    local extracted
    extracted="$(find "$work" -mindepth 1 -maxdepth 1 -type d -name 'kubelynx-v*' | head -n1)"
    if [[ -z "$extracted" ]] || ! kubelynx::is_runtime_tree "$extracted"; then
        echo "[ERROR] Release archive did not contain a KubeLynx runtime tree." >&2
        exit 1
    fi
    kubelynx::copy_runtime "$extracted" "$dest"
    chmod +x "$dest/bin/kubelynx.sh"
    kubelynx::write_meta "$dest" "release" "github-release:${latest_tag}"
    mkdir -p "$(kubelynx::bin_dir)"
    ln -sfn "$dest/bin/kubelynx.sh" "$LINK"
    echo "[OK] Updated to $latest_tag"
}

case "$MODE" in
    git | dev)
        if ! update_git "$TARGET"; then
            echo "[ERROR] This installation is not a Git clone; cannot git pull." >&2
            echo "[INFO] Reinstall from a GitHub Release, or clone the repository." >&2
            exit 1
        fi
        ;;
    release | *)
        if [[ -d "$TARGET/.git" ]]; then
            update_git "$TARGET"
        else
            update_release "$TARGET"
        fi
        ;;
esac

echo "[OK] Update complete."
exit 0
