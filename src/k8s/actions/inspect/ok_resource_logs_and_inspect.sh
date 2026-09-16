#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
get_pod_logs_all() {
    local NAMESPACE=$(select_namespace) || return 1

    if [[ "$NAMESPACE" == "all" ]]; then
        local line ns pod
        line=$(kubectl get pods --all-namespaces --no-headers | awk '{print $2 " (ns:" $1 ")"}' | fzf --prompt="📦 Select a pod: ")
        [[ -z "$line" ]] && frame_message "$RED" "No pod selected." && return 1
        pod=$(echo "$line" | awk '{print $1}')
        ns=$(echo "$line" | sed -E 's/.*\(ns:([^)]*)\).*/\1/')

        check_pod_status_for_logs "$pod" "$ns" || return 1

        print_separator
        kubectl logs "$pod" -n "$ns" --all-containers=true
    else
        local pod=$(select_pod "$NAMESPACE") || return 1

        check_pod_status_for_logs "$pod" "$NAMESPACE" || return 1

        print_separator
        kubectl logs "$pod" -n "$NAMESPACE" --all-containers=true
    fi
}

get_pod_logs_errors() {
    local NAMESPACE=$(select_namespace) || return 1

    if [[ "$NAMESPACE" == "all" ]]; then
        local line ns pod
        line=$(kubectl get pods --all-namespaces --no-headers | awk '{print $2 " (ns:" $1 ")"}' | fzf --prompt="❗ Select a pod for errors: ")
        [[ -z "$line" ]] && frame_message "$RED" "No pod selected." && return 1
        pod=$(echo "$line" | awk '{print $1}')
        ns=$(echo "$line" | sed -E 's/.*\(ns:([^)]*)\).*/\1/')

        check_pod_status_for_logs "$pod" "$ns" || return 1

        print_separator
        kubectl logs "$pod" -n "$ns" --all-containers=true | grep -iE 'error|fail|exception'
    else
        local pod=$(select_pod "$NAMESPACE") || return 1

        check_pod_status_for_logs "$pod" "$NAMESPACE" || return 1

        print_separator
        kubectl logs "$pod" -n "$NAMESPACE" --all-containers=true | grep -iE 'error|fail|exception'
    fi
}

get_pod_logs_warnings() {
    local NAMESPACE=$(select_namespace) || return 1

    if [[ "$NAMESPACE" == "all" ]]; then
        local line ns pod
        line=$(kubectl get pods --all-namespaces --no-headers | awk '{print $2 " (ns:" $1 ")"}' | fzf --prompt="⚠️  Select a pod for warnings: ")
        [[ -z "$line" ]] && frame_message "$RED" "No pod selected." && return 1
        pod=$(echo "$line" | awk '{print $1}')
        ns=$(echo "$line" | sed -E 's/.*\(ns:([^)]*)\).*/\1/')

        check_pod_status_for_logs "$pod" "$ns" || return 1

        print_separator
        kubectl logs "$pod" -n "$ns" --all-containers=true | grep -i 'warn'
    else
        local pod=$(select_pod "$NAMESPACE") || return 1

        check_pod_status_for_logs "$pod" "$NAMESPACE" || return 1

        print_separator
        kubectl logs "$pod" -n "$NAMESPACE" --all-containers=true | grep -i 'warn'
    fi
}

get_pod_logs_pattern() {
    local NAMESPACE=$(select_namespace) || return 1
    echo -ne "${YELLOW}🔍 Enter log pattern to search (e.g. timeout, 404, panic): ${RESET}"
    read -r pattern
    [[ -z "$pattern" ]] && frame_message "$RED" "No pattern entered." && return 1

    if [[ "$NAMESPACE" == "all" ]]; then
        local line ns pod
        line=$(kubectl get pods --all-namespaces --no-headers | awk '{print $2 " (ns:" $1 ")"}' | fzf --prompt="🔎 Select a pod: ")
        [[ -z "$line" ]] && frame_message "$RED" "No pod selected." && return 1
        pod=$(echo "$line" | awk '{print $1}')
        ns=$(echo "$line" | sed -E 's/.*\(ns:([^)]*)\).*/\1/')

        check_pod_status_for_logs "$pod" "$ns" || return 1

        print_separator
        kubectl logs "$pod" -n "$ns" --all-containers=true | grep -i --color=always "$pattern"
    else
        local pod=$(select_pod "$NAMESPACE") || return 1

        check_pod_status_for_logs "$pod" "$NAMESPACE" || return 1

        print_separator
        kubectl logs "$pod" -n "$NAMESPACE" --all-containers=true | grep -i --color=always "$pattern"
    fi
}

get_pod_logs_smart() {
    local options=("All Logs" "Errors" "Warnings" "Custom Pattern")
    local choice=$(printf "%s\n" "${options[@]}" | fzf --prompt="📋 Select log type ❯ ")
    case "$choice" in
        "All Logs") get_pod_logs_all ;;
        "Errors") get_pod_logs_errors ;;
        "Warnings") get_pod_logs_warnings ;;
        "Custom Pattern") get_pod_logs_pattern ;;
        *) frame_message "$RED" "Cancelled." ;;
    esac
}

get_pod_logs_stern_filter() {
    local namespace
    #  namespace=$(kubectl get ns --no-headers | awk '{print $1}' | fzf --prompt="Select Namespace: ") || return
    namespace=$(select_namespace) || return 1

    local pod
    pod=$(kubectl get pods -n "$namespace" --no-headers | awk '{print $1}' | fzf --prompt="Select Pod: ") || return

    local container
    container=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath="{.spec.containers[*].name}" | tr ' ' '\n' | fzf --prompt="Select Container (optional): ") || container=""

    echo -e "\nChoose a log filter pattern:"
    local pattern
    pattern=$(printf "error\nwarning\ninfo\ncustom\n" | fzf --prompt="Filter Pattern: ") || pattern=""

    if [[ $pattern == "custom" ]]; then
        read -rp "Enter your custom regex pattern: " pattern
    fi

    echo -e "\nInclude or exclude this pattern?"
    local mode
    mode=$(printf "include\nexclude\nnone\n" | fzf --prompt="Filter Mode: ") || mode="none"

    read -rp "How many lines to show (default 100): " tail
    tail=${tail:-100}

    echo -e "\n\033[1;33mLaunching stern logs...\033[0m"
    echo "-----------------------------------"
    local -a stern_args=("$pod" -n "$namespace" --tail "$tail")
    [[ -n ${container:-} ]] && stern_args+=(-c "$container")
    [[ $mode == "include" ]] && stern_args+=(--include "$pattern")
    [[ $mode == "exclude" ]] && stern_args+=(--exclude "$pattern")
    stern "${stern_args[@]}"
}
