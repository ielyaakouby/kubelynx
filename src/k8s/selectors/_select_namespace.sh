#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
set_default_namespace() {
    local namespace="${1:-}"
    local current_namespace

    # Sélection interactive si aucun namespace fourni
    if [[ -z "$namespace" ]]; then
        namespace=$(select_namespace) || return 1
    fi

    # Récupération de l'ancien namespace
    current_namespace=$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null)
    current_namespace="${current_namespace:-default}"

    print_separator
    echo -e "[i] Current context       : ${CLR_INFO}$(kubectl config current-context)${CLR_RESET}"
    echo -e "[+] Changing namespace    : ${CLR_WARN}$current_namespace${CLR_RESET} → ${CLR_SUCCESS}$namespace${CLR_RESET}"

    if kubectl config set-context --current --namespace="$namespace" &>/dev/null; then
        echo -e "\n ${CLR_BOLD}${CLR_SUCCESS}[✓] Default namespace successfully updated!${CLR_RESET}"
        echo -e " ${CLR_BOLD}[+] New default namespace :${CLR_RESET} ${CLR_CONTEXT}$(kubectl config view --minify -o jsonpath='{..namespace}')${CLR_RESET}"
    else
        echo -e "\n ${CLR_BOLD}${CLR_ERROR}[x] Failed to set default namespace to '${CLR_WARN}$namespace${CLR_ERROR}'.${CLR_RESET}"
        return 1
    fi
}

list_namespace_labels() {
    print_separator
    echo -e "\e[1;33mSelect a namespace to view labels (or choose 'All Namespaces'):\e[0m"

    local namespace
    namespace=$(printf "All Namespaces\n%s" "$(kubectl get ns -o custom-columns=":metadata.name" --no-headers)" \
        | fzf --prompt="Namespace ❯ " --border --height=40%) || return

    if [[ "$namespace" == "All Namespaces" ]]; then
        kubectl get ns --show-labels
    else
        select_namespace "$namespace"
        kubectl get ns "$namespace" --show-labels
    fi
}
# Cache namespace list
