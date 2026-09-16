#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Shared installer path helpers. Sourced by install/update/uninstall and tests.
# Do not enable `set -u` here; callers decide shell options.

# Repository / project root (directory that contains VERSION and bin/).
kubelynx::source_root() {
    local here
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || return 1
    printf '%s\n' "$here"
}

# Default user-space application directory.
kubelynx::install_dir() {
    printf '%s\n' "${KUBELYNX_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/kubelynx}"
}

# Default user-space executable directory.
kubelynx::bin_dir() {
    printf '%s\n' "${KUBELYNX_BIN_DIR:-${HOME}/.local/bin}"
}

kubelynx::bin_link() {
    printf '%s\n' "$(kubelynx::bin_dir)/kubelynx"
}

# Pre-rename (Kubediag) user-space paths. Kept only for migration/uninstall.
kubelynx::legacy_install_dir() {
    printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/kubediag"
}

kubelynx::legacy_bin_link() {
    printf '%s\n' "$(kubelynx::bin_dir)/kubediag"
}

kubelynx::legacy_home_dir() {
    printf '%s\n' "${HOME}/.kubediag/kubediag"
}

kubelynx::repo_url() {
    printf '%s\n' "${KUBELYNX_REPO_URL:-https://github.com/ielyaakouby/kubelynx}"
}

kubelynx::api_url() {
    printf '%s\n' "${KUBELYNX_API_URL:-https://api.github.com/repos/ielyaakouby/kubelynx}"
}

# True when a directory looks like a KubeLynx source/runtime tree.
# bin/kubediag.sh is accepted only so a pre-rename install can be detected
# and migrated.
kubelynx::is_runtime_tree() {
    local dir="${1:-}"
    [[ -n "$dir" ]] || return 1
    [[ -f "$dir/VERSION" && -d "$dir/src/k8s" ]] || return 1
    [[ -f "$dir/bin/kubelynx.sh" || -f "$dir/bin/kubediag.sh" ]]
}

# Refuse to delete anything that is not a KubeLynx-owned path.
# Allowed: the configured install dir, or a directory whose final component is
# exactly "kubelynx" or the pre-rename "kubediag" under $HOME or $XDG_DATA_HOME.
kubelynx::is_safe_install_dir() {
    local dir="${1:-}"
    local expected home_real xdg_real dir_real base
    [[ -n "$dir" ]] || return 1
    [[ "$dir" != "/" ]] || return 1
    [[ "$dir" != "$HOME" ]] || return 1
    expected="$(kubelynx::install_dir)"
    if [[ "$dir" == "$expected" ]]; then
        return 0
    fi
    home_real="$(cd "$HOME" 2>/dev/null && pwd)" || return 1
    xdg_real="$(cd "${XDG_DATA_HOME:-$HOME/.local/share}" 2>/dev/null && pwd)" || xdg_real=""
    dir_real="$(cd "$dir" 2>/dev/null && pwd)" || dir_real="$dir"
    base="$(basename "$dir_real")"
    [[ "$base" == "kubelynx" || "$base" == "kubediag" ]] || return 1
    case "$dir_real" in
        "$home_real"/* | "$xdg_real"/*) return 0 ;;
        *) return 1 ;;
    esac
}

# Prefer .kubelynx-meta; fall back to the pre-rename .kubediag-meta file.
kubelynx::meta_file() {
    local dest="${1:-}"
    if [[ -n "$dest" && -f "$dest/.kubelynx-meta" ]]; then
        printf '%s\n' "$dest/.kubelynx-meta"
    elif [[ -n "$dest" && -f "$dest/.kubediag-meta" ]]; then
        printf '%s\n' "$dest/.kubediag-meta"
    else
        printf '%s\n' "${dest}/.kubelynx-meta"
    fi
}

# Move a previous Kubediag user-space install onto KubeLynx paths when safe.
# Never deletes an ambiguous extra copy; prints instructions instead.
kubelynx::migrate_legacy_install() {
    local new_dest="${1:-}"
    local src="${2:-}"
    local old_dest old_link
    [[ -n "$new_dest" ]] || return 0
    old_dest="$(kubelynx::legacy_install_dir)"
    old_link="$(kubelynx::legacy_bin_link)"

    if [[ -e "$old_dest" && "$old_dest" != "$new_dest" ]]; then
        if [[ -n "$src" && "$old_dest" == "$src" ]]; then
            echo "[INFO] Previous Kubediag path $old_dest is this source tree; it was not moved."
        elif [[ -d "$new_dest" ]]; then
            echo "[INFO] Found a previous Kubediag install at $old_dest"
            echo "[INFO] KubeLynx is already present at $new_dest; the old directory was left unchanged."
            echo "[INFO] After you confirm kubelynx works, remove the old directory yourself if you no longer need it."
        elif [[ -d "$old_dest" ]] && kubelynx::is_safe_install_dir "$old_dest"; then
            mkdir -p "$(dirname "$new_dest")"
            if mv "$old_dest" "$new_dest"; then
                echo "[OK] Migrated previous Kubediag data directory to $new_dest"
            else
                echo "[WARN] Could not migrate $old_dest; continuing with a fresh KubeLynx install."
            fi
        else
            echo "[INFO] Found $old_dest but it was not migrated (unexpected layout)."
            echo "[INFO] Install continues into $new_dest."
        fi
    fi

    if [[ -L "$old_link" ]]; then
        local target
        target="$(readlink "$old_link" || true)"
        case "$target" in
            */kubediag.sh | */kubelynx.sh)
                rm -f "$old_link"
                echo "[OK] Removed deprecated Kubediag command symlink $old_link"
                ;;
            *)
                echo "[WARN] $old_link exists and does not look like a KubeLynx/Kubediag symlink; leaving it in place."
                ;;
        esac
    fi
}

kubelynx::read_version_file() {
    local file="${1:-}"
    local version=""
    if [[ -n "$file" && -f "$file" ]]; then
        version="$(tr -d '[:space:]' <"$file")"
    fi
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.]+)?$ ]]; then
        return 1
    fi
    printf '%s\n' "$version"
}

kubelynx::detect_install_mode() {
    local dir="${1:-}"
    if [[ -d "$dir/.git" ]]; then
        printf '%s\n' "git"
    else
        printf '%s\n' "release"
    fi
}

kubelynx::write_meta() {
    local dest="$1"
    local mode="$2"
    local source="${3:-}"
    mkdir -p "$dest"
    cat >"$dest/.kubelynx-meta" <<EOF
MODE=${mode}
SOURCE=${source}
VERSION=$(kubelynx::read_version_file "$dest/VERSION" 2>/dev/null || echo unknown)
INSTALLED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    rm -f "$dest/.kubediag-meta"
}

kubelynx::meta_value() {
    local file="$1"
    local key="$2"
    [[ -f "$file" ]] || return 1
    awk -F= -v k="$key" '$1 == k { print substr($0, index($0, "=") + 1); exit }' "$file"
}

# Copy the runtime tree into the install directory.
kubelynx::copy_runtime() {
    local src="$1"
    local dest="$2"
    local item
    mkdir -p "$dest"
    for item in bin config installer src LICENSE NOTICE README.md VERSION CHANGELOG.md; do
        if [[ -e "$src/$item" ]]; then
            rm -rf "${dest:?}/${item}"
            cp -a "$src/$item" "$dest/$item"
        fi
    done
    if [[ -d "$src/.git" ]]; then
        rm -rf "${dest:?}/.git"
        cp -a "$src/.git" "$dest/.git"
    fi
}

kubelynx::path_contains() {
    local needle="$1"
    case ":${PATH}:" in
        *":${needle}:"*) return 0 ;;
        *) return 1 ;;
    esac
}

# Print a PATH hint. Never edit shell rc files.
kubelynx::print_path_hint() {
    local bin_dir="$1"
    if kubelynx::path_contains "$bin_dir"; then
        return 0
    fi
    cat <<EOF

[i] ${bin_dir} is not in PATH.
    Add it for the current session:

      export PATH="${bin_dir}:\$PATH"

    Persist it in your shell configuration if you want it permanently
    (for example ~/.profile, ~/.bashrc, ~/.zshrc). KubeLynx does not
    edit those files automatically.
EOF
}
