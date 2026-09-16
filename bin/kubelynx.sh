#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2034
# SPDX-License-Identifier: Apache-2.0
#
# kubelynx — Interactive Kubernetes Diagnostics & Management
# Copyright 2026 Ismail Elyaakouby
# https://github.com/ielyaakouby/kubelynx
#
# Usage:
#   kubelynx              Launch interactive menu
#   kubelynx ok           Load modules only (library mode)
#   kubelynx --version    Print version
#   kubelynx --help       Show usage
#

# Strict mode when executed as a program. Do not change the caller's options
# when this file is sourced as a library (`source bin/kubelynx.sh ok`).
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -euo pipefail
fi

###########################################
# Path and version
###########################################

# Resolve the install/source root without GNU `readlink -f`.
# Follows the entrypoint symlink so release installs work from ~/.local/bin.
kubelynx::resolve_root() {
    local source="${BASH_SOURCE[0]}"
    local dir target
    while [[ -L "$source" ]]; do
        dir="$(cd "$(dirname "$source")" && pwd)" || return 1
        target="$(readlink "$source")"
        if [[ "$target" == /* ]]; then
            source="$target"
        else
            source="${dir}/${target}"
        fi
    done
    dir="$(cd "$(dirname "$source")/.." && pwd)" || return 1
    printf '%s\n' "$dir"
}

SCRIPT_DIR="$(kubelynx::resolve_root)"

# VERSION is the single source of truth. A hardcoded fallback is intentionally
# avoided so a missing or broken VERSION file cannot silently report a stale
# number. `--version` prints "unknown" and exits non-zero in that case.
kubelynx::read_version() {
    local version_file="${SCRIPT_DIR}/VERSION"
    local version=""
    if [[ -f "$version_file" ]]; then
        version="$(tr -d '[:space:]' <"$version_file")"
    fi
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.]+)?$ ]]; then
        return 1
    fi
    printf '%s\n' "$version"
}

kubelynx::print_version() {
    local version
    if version="$(kubelynx::read_version)"; then
        printf 'KubeLynx v%s\n' "$version"
        return 0
    fi
    printf 'KubeLynx vunknown\n' >&2
    printf 'VERSION file missing or malformed in %s\n' "$SCRIPT_DIR" >&2
    return 1
}

kubelynx::usage() {
    cat <<'EOF'
KubeLynx — Interactive Kubernetes diagnostics and management CLI

Usage:
  kubelynx              Launch the interactive menu
  kubelynx ok           Load modules only (library mode)
  kubelynx --version    Print version
  kubelynx --help       Show this help

KubeLynx uses your existing kubectl / KUBECONFIG credentials. It does not
grant additional Kubernetes permissions.
EOF
}

###########################################
# Temporary files
###########################################

TMPDIR="${TMPDIR:-/tmp}"
OK_FILE=""
NOK_FILE=""
TMP_ALL_PODS=""
TMP_NODE_REPORT=""
TMP_NODE_COUNTS=""
TEMP_FILES_FILE=""
tracked_functions=""

NAMESPACE="${NAMESPACE:-}"
POD_NAME="${POD_NAME:-}"
SVC_NAME="${SVC_NAME:-}"
INGRESSE_NAME="${INGRESSE_NAME:-}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-}"
STATEFULSET_NAME="${STATEFULSET_NAME:-}"
DAEMONSET_NAME="${DAEMONSET_NAME:-}"
NODE_NAME="${NODE_NAME:-}"
CONFIGMAP_NAME="${CONFIGMAP_NAME:-}"
RESOURCE_NAME="${RESOURCE_NAME:-}"

# Register a file created by this process for cleanup on exit.
register_temp_file() {
    local file="$1"
    if [[ -n "$file" && -n "${TEMP_FILES_FILE:-}" && -f "$TEMP_FILES_FILE" ]]; then
        printf '%s\n' "$file" >>"$TEMP_FILES_FILE"
    fi
}

kubelynx::init_temp_files() {
    OK_FILE="$(mktemp "${TMPDIR}/kubelynx.ok.XXXXXX")"
    NOK_FILE="$(mktemp "${TMPDIR}/kubelynx.nok.XXXXXX")"
    TMP_ALL_PODS="$(mktemp "${TMPDIR}/kubelynx.pods.XXXXXX")"
    TMP_NODE_REPORT="$(mktemp "${TMPDIR}/kubelynx.nodes.XXXXXX")"
    TMP_NODE_COUNTS="$(mktemp "${TMPDIR}/kubelynx.counts.XXXXXX")"
    TEMP_FILES_FILE="$(mktemp "${TMPDIR}/kubelynx.files.XXXXXX")"
    register_temp_file "$OK_FILE"
    register_temp_file "$NOK_FILE"
    register_temp_file "$TMP_ALL_PODS"
    register_temp_file "$TMP_NODE_REPORT"
    register_temp_file "$TMP_NODE_COUNTS"
}

# Delete only files registered by this process. Do not glob /tmp.
cleanup() {
    local file
    if [[ -n "${TEMP_FILES_FILE:-}" && -f "$TEMP_FILES_FILE" ]]; then
        while IFS= read -r file || [[ -n "$file" ]]; do
            if [[ -n "$file" && -e "$file" ]]; then
                rm -f -- "$file"
            fi
        done <"$TEMP_FILES_FILE"
        rm -f -- "$TEMP_FILES_FILE"
    fi
    for file in "${OK_FILE:-}" "${NOK_FILE:-}" "${TMP_ALL_PODS:-}" "${TMP_NODE_REPORT:-}" "${TMP_NODE_COUNTS:-}"; do
        [[ -n "$file" && -e "$file" ]] && rm -f -- "$file"
    done
    return 0
}

###########################################
# kubelynx::load_modules
###########################################
kubelynx::load_modules() {
    local defaults_file="${SCRIPT_DIR}/config/defaults.sh"
    if [[ -f "$defaults_file" ]]; then
        # shellcheck source=../config/defaults.sh
        source "$defaults_file" || {
            echo "Error: Failed to load $defaults_file" >&2
            return 1
        }
    fi

    local menu_dir="${SCRIPT_DIR}/src/k8s/menu"
    if [[ -d "$menu_dir" ]]; then
        local pri script bname
        for pri in menu_ui_enhanced.sh main_menu_enhanced.sh main_menu_ok.sh; do
            [[ -f "${menu_dir}/${pri}" ]] || continue
            source "${menu_dir}/${pri}" || {
                echo "Error: Failed to load $pri" >&2
                return 1
            }
        done

        for script in "$menu_dir"/*.sh; do
            [[ -f "$script" ]] || continue
            bname="$(basename "$script")"
            case "$bname" in
                menu_ui_enhanced.sh | main_menu_enhanced.sh | main_menu_ok.sh | main_menu_refactored.sh) continue ;;
            esac
            source "$script" || {
                echo "Error: Failed to load $script" >&2
                return 1
            }
        done
    fi

    local before_funcs after_funcs
    before_funcs="$(declare -F | awk '{print $3}' | sort)"

    local -a paths=(
        "${SCRIPT_DIR}/src/k8s/common"
        "${SCRIPT_DIR}/src/k8s/core"
        "${SCRIPT_DIR}/src/k8s/helpers"
        "${SCRIPT_DIR}/src/k8s/selectors"
        "${SCRIPT_DIR}/src/k8s/tools"
        "${SCRIPT_DIR}/src/k8s/monitoring"
        "${SCRIPT_DIR}/src/k8s/troubleshoot"
        "${SCRIPT_DIR}/src/k8s/actions/config"
        "${SCRIPT_DIR}/src/k8s/actions/inspect"
        "${SCRIPT_DIR}/src/k8s/actions/networking"
        "${SCRIPT_DIR}/src/k8s/actions/pods"
        "${SCRIPT_DIR}/src/k8s/actions/rollout"
        "${SCRIPT_DIR}/src/k8s/others"
    )

    local dir
    for dir in "${paths[@]}"; do
        if [[ ! -d "$dir" ]]; then
            continue
        fi
        for script in "$dir"/*.sh; do
            [[ -f "$script" ]] || continue
            source "$script" || {
                echo "Error: Failed to load $script" >&2
                return 1
            }
        done
    done

    after_funcs="$(declare -F | awk '{print $3}' | sort)"
    tracked_functions="$(comm -13 <(printf '%s\n' "$before_funcs") <(printf '%s\n' "$after_funcs"))"
}

###########################################
# kubelynx::cleanup_modules
###########################################
kubelynx::cleanup_modules() {
    local func
    if [[ -n "${tracked_functions:-}" ]]; then
        # shellcheck disable=SC2086
        for func in $tracked_functions; do
            unset -f "$func" 2>/dev/null || true
        done
    fi
}

###########################################
# kubelynx::run_main
###########################################
kubelynx::run_main() {
    trap cleanup EXIT
    kubelynx::init_temp_files

    if ! kubelynx::load_modules; then
        echo "Error: Failed to load required modules" >&2
        return 1
    fi

    if ! cluster::check_connectivity; then
        return 1
    fi

    menu::select_main_action
}

###########################################
# Entry point
###########################################
kubelynx::main() {
    case "${1:-}" in
        ok)
            kubelynx::load_modules
            ;;
        --version | -v)
            kubelynx::print_version
            ;;
        --help | -h)
            kubelynx::usage
            ;;
        "")
            kubelynx::run_main
            ;;
        *)
            echo "Unknown option: $1" >&2
            kubelynx::usage >&2
            return 2
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    kubelynx::main "$@"
fi
