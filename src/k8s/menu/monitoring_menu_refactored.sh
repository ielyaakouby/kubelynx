#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
# ============================================================================
# Monitoring & Usage Menu - Refactored
# ============================================================================

menu::monitoring_menu() {
    while true; do
        local options=(
            "← Go Back"
            "□ View: Kubernetes Events"
            "□ View: Pods Status by Node"
            "□ View: Node Status Conditions"
            "□ View: Node Events"
            "? Monitor: Top Pods (CPU/Memory)"
            "? Monitor: Top Nodes (CPU/Memory)"
            "? Monitor: Pods Status"
            "? Monitor: Pod Resource Allocation"
            "? Monitor: Node Resource Allocation"
            "? Monitor: Resource Usage Over Time"
            "↑ Go Home"
        )

        local selected_action
        selected_action=$(printf "%s\n" "${options[@]}" \
            | fzf \
                --prompt="Main Menu ❯ Monitoring & Usage ❯ " \
                --border=rounded \
                --border-label="[KD] Kubernetes doctor [KD]" \
                --height=40% \
                --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || return

        case "$selected_action" in
            *"Go Back") return 0 ;;
            *"Go Home") menu::select_main_action ;;
            *"View: Kubernetes Events" | *"□ View: Kubernetes Events")
                output=$(kubectl get events --all-namespaces --sort-by='.metadata.creationTimestamp' --no-headers 2>/dev/null | awk '$3 != "Normal" {print $0}')
                if [[ -z "$output" ]]; then
                    echo -e "\e[32mNo abnormal events detected in all namespaces.\e[0m"
                else
                    echo -e "\e[38;5;196m$output\e[0m"
                fi
                print_separator
                ;;
            *"View: Pods Status by Node" | *"□ View: Pods Status by Node")
                ok_check_node_pods
                print_separator
                ;;
            *"View: Node Status Conditions" | *"□ View: Node Status Conditions")
                node_status_conditions_overview
                print_separator
                ;;
            *"View: Node Events" | *"□ View: Node Events")
                get_node_events
                print_separator
                ;;
            *"Monitor: Top Pods (CPU/Memory)" | *"? Monitor: Top Pods (CPU/Memory)")
                kube_top_pods
                print_separator
                ;;
            *"Monitor: Top Nodes (CPU/Memory)" | *"? Monitor: Top Nodes (CPU/Memory)")
                kube_top_nodes
                print_separator
                ;;
            *"Monitor: Pods Status" | *"? Monitor: Pods Status")
                monitor_pods_status || true
                print_separator
                ;;
            *"Monitor: Pod Resource Allocation" | *"? Monitor: Pod Resource Allocation")
                monitor_pod_resources_allocation || true
                print_separator
                ;;
            *"Monitor: Node Resource Allocation" | *"? Monitor: Node Resource Allocation")
                monitor_node_allocated_resources
                print_separator
                ;;
            *"Monitor: Resource Usage Over Time" | *"? Monitor: Resource Usage Over Time")
                monitor_pod_usage_over_time
                print_separator
                ;;
            *)
                frame_message "$RED" "❌ Invalid option selected. Try again."
                ;;
        esac
    done
}
