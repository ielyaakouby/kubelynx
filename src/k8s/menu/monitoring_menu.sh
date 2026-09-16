#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
select_monitor_menu() {
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color

    while true; do
        options=(
            "← Go Back"
            "> Get Kubernetes Events"
            "> Check Pods Status by Node"
            "> Overview Node Status Conditions"
            "> View Node Events"
            "→ Top Pods by CPU/Memory"
            "→ Top Node by CPU/Memory"
            "> Monitor Pods Status"
            "> Monitor Pod Resource Allocation"
            "> Monitor Node Resource Allocation"
            "> Monitor Resource Usage Over Period"
            "↑ Go Home"
        )

        local selected_action
        selected_action=$(printf "%s\n" "${options[@]}" \
            | fzf \
                --prompt="Main Menu ❯ Monitor Menu ❯ " \
                --border=rounded \
                --border-label="🩺 Kubernetes doctor 🩺" \
                --height=40% \
                --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow")

        case $selected_action in
            *"Go Back") return 0 ;;
            *"Top Pods by CPU/Memory") kube_top_pods ;;
            *"Top Node by CPU/Memory") kube_top_nodes ;;
            *"Go Home") menu::select_main_action ;;
            *"View Node Events")
                get_node_events
                print_separator
                ;;
            *"Check Pods Status by Node")
                ok_check_node_pods
                print_separator
                ;;
            *"Monitor Node Resource Allocation")
                monitor_node_allocated_resources
                print_separator
                ;;
            *"Get Kubernetes Events")
                output=$(kubectl get events --all-namespaces --sort-by='.metadata.creationTimestamp' --no-headers 2>/dev/null | awk '$3 != "Normal" {print $0}')
                if [[ -z "$output" ]]; then
                    echo -e "\e[32mNo abnormal events detected in all namespaces.\e[0m"
                else
                    echo -e "\e[38;5;196m$output\e[0m"
                fi
                ;;
            *"Overview Node Status Conditions")
                node_status_conditions_overview
                print_separator
                ;;
            *"Monitor Pods Status")
                monitor_pods_status || exit 1
                print_separator
                ;;
            *"Monitor Pod Resource Allocation")
                monitor_pod_resources_allocation || exit 1
                print_separator
                ;;
            *"Monitor Resource Usage Over Period")
                monitor_pod_usage_over_time
                print_separator
                ;;
            *)
                frame_message "${RED}" "Invalid option selected."
                ;;
        esac
    done
}
