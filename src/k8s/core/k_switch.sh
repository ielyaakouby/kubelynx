#!/usr/bin/env bash
# Shared globals such as color codes are defined by sibling modules.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046

ok_k_switch() {
    local kubeconfig_dir="${KUBELYNX_KUBECONFIG_DIR:-${HOME}/.kube}"
    local COLOR_YELLOW="\e[1;33m"
    local COLOR_RED="\e[1;31m"
    local COLOR_RESET="\e[0m"

    if [[ ! -d "$kubeconfig_dir" ]]; then
        echo -e "${COLOR_RED}Error:${COLOR_RESET} Directory $kubeconfig_dir does not exist."
        echo "Set KUBELYNX_KUBECONFIG_DIR to a directory of kubeconfig files."
        return 1
    fi

    local selected_file
    # Use find instead of ls to avoid word-splitting surprises.
    selected_file="$(find "$kubeconfig_dir" -maxdepth 1 -type f -print 2>/dev/null | fzf --exact --prompt='Select kubeconfig: ')" || true

    if [[ -n "$selected_file" ]]; then
        export KUBECONFIG="$selected_file"
        echo -e "${COLOR_YELLOW}KUBECONFIG set to:${COLOR_RESET} $KUBECONFIG"
    else
        echo -e "${COLOR_RED}No file selected. KUBECONFIG not changed.${COLOR_RESET}"
    fi
}
