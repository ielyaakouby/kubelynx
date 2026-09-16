#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
function display_secret_content() {
    local NAMESPACE="${1}"
    local secret_name="${2}"
    local secret_keys
    local secret_key
    local content

    if [ -z "$NAMESPACE" ]; then
        read -r -p "Enter namespace: " NAMESPACE
        if [[ -z $NAMESPACE ]]; then
            NAMESPACE=$(select_namespace) || exit 1
            echo -e "${COLOR_CYAN}namespace selected => $NAMESPACE ${COLOR_RESET}"
        else
            echo -e "${COLOR_CYAN}Using provided namespace => $NAMESPACE ${COLOR_RESET}"
        fi
    fi

    if [ -z "$secret_name" ]; then
        read -r -p "Enter Secret name: " secret_name
        if [[ -z $secret_name ]]; then
            secret_name=$(select_secret_name "$NAMESPACE") || exit 1
            echo -e "${COLOR_CYAN}secret selected => $secret_name ${COLOR_RESET}"
        else
            echo -e "${COLOR_CYAN}Using provided Secret name => $secret_name ${COLOR_RESET}"
        fi
    fi

    echo -e "${COLOR_YELLOW}Retrieving keys from Secret: $secret_name in namespace: $NAMESPACE...${COLOR_RESET}"
    secret_keys=$(kubectl -n "$NAMESPACE" get secret "$secret_name" -o json | jq -r '.data | keys[]' 2>/dev/null)
    secret_key=$(echo "$secret_keys" | fzf --prompt="Select a key: ")

    if [ -n "$secret_key" ]; then
        echo -e "${COLOR_YELLOW}Selected key: $secret_key ${COLOR_RESET}"
        content=$(kubectl -n "$NAMESPACE" get secret "$secret_name" -o json | jq -r ".data[\"$secret_key\"]" 2>/dev/null)

        if [[ "$content" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] && [ $((${#content} % 4)) -eq 0 ]; then
            local decoded tmp_secret
            decoded="$(printf '%s' "$content" | base64 --decode 2>/dev/null || true)"
            tmp_secret="$(create_temp_file "_secret.txt")"
            printf '%s\n' "$decoded" >"$tmp_secret"
            kubelynx::run_in_new_terminal "secret $secret_name / $secret_key ($NAMESPACE)" "cat '$tmp_secret'; echo ''; read"
        else
            echo -e "${COLOR_GREEN}$secret_key:${COLOR_RESET}"
            echo "$content"
        fi
        echo
    else
        echo -e "${COLOR_RED}No key selected.${COLOR_RESET}"
    fi
}

k8s_get_matching_secrets() {
    local NAMESPACE="$1"
    local search_string="$2"

    if [ -z "$NAMESPACE" ] || [ -z "$search_string" ]; then
        k8s_get_matching_secrets_display_help
    fi

    kubectl -n "$NAMESPACE" get secret --no-headers | awk '{print $1}' | while read -r secret_name; do
        kubectl -n "$NAMESPACE" get secret "$secret_name" -o jsonpath='{.data}' \
            | jq -r 'to_entries[] | "\(.key): \(.value | @base64d)"' \
            | grep "$search_string"
    done
}

display_configmap_content() {
    local NAMESPACE="${1}"
    local configmap_name="${2}"
    local configmap_keys
    local configmap_key
    local content

    if [ -z "$NAMESPACE" ]; then
        trap menu::select_main_action SIGINT
        read -r -p "Enter namespace: " NAMESPACE
        if [[ -z $NAMESPACE ]]; then
            NAMESPACE=$(select_namespace) || exit 1
            echo -e "${COLOR_CYAN}namespace selected => $NAMESPACE ${COLOR_RESET}"
        else
            echo -e "${COLOR_CYAN}Using provided namespace => $NAMESPACE ${COLOR_RESET}"
        fi
    fi

    if [ -z "$configmap_name" ]; then
        read -r -p "Enter ConfigMap name: " configmap_name
        if [[ -z $configmap_name ]]; then
            configmap_name=$(select_configmap_name "$NAMESPACE") || exit 1
            echo -e "${COLOR_CYAN}configmap selected => $configmap_name ....${COLOR_RESET}"
        else
            echo -e "${COLOR_CYAN}Using provided ConfigMap name => $configmap_name ${COLOR_RESET}"
        fi
    fi

    echo -e "${COLOR_YELLOW}Retrieving keys from ConfigMap: $configmap_name in namespace: $NAMESPACE...${COLOR_RESET}"
    configmap_keys=$(kubectl -n "$NAMESPACE" get cm "$configmap_name" -o json | jq -r '.data | keys[]' 2>/dev/null)
    configmap_key=$(echo "$configmap_keys" | fzf --prompt="Select a key: ")
    echo "configmap key selected => $configmap_key"

    if [ -n "$configmap_key" ]; then
        echo -e "${COLOR_YELLOW}Selected key: $configmap_key ....${COLOR_RESET}"
        content=$(kubectl -n "$NAMESPACE" get cm "$configmap_name" -o json | jq -r ".data[\"$configmap_key\"]" 2>/dev/null)

        if [[ "$content" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] && [ $((${#content} % 4)) -eq 0 ]; then
            echo -e "${COLOR_GREEN}$configmap_key:${COLOR_RESET}"
            local decoded tmp_cm
            decoded="$(printf '%s' "$content" | base64 --decode 2>/dev/null || true)"
            tmp_cm="$(create_temp_file "_configmap.txt")"
            printf '%s\n' "$decoded" >"$tmp_cm"
            kubelynx::run_in_new_terminal "configmap $configmap_name / $configmap_key ($NAMESPACE)" "cat '$tmp_cm'; echo ''; read"
        else
            echo -e "${COLOR_GREEN}$configmap_key:${COLOR_RESET}"
            echo "$content"
        fi
        echo
    else
        echo -e "${COLOR_RED}No key selected.${COLOR_RESET}"
    fi
}

# JSON output support
