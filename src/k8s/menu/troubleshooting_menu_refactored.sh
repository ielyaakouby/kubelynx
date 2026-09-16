#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
# ============================================================================
# Troubleshooting Tools Menu - Refactored
# ============================================================================

menu::troubleshooting_menu() {
    while true; do
        local options=(
            "← Go Back"
            "> Diagnose: Pod Restart Issues"
            "> Diagnose: Network Connectivity"
            "> Diagnose: Pod Issues"
            "□ View: Pods by Status"
            "□ View: Pod Logs (Smart)"
            "□ View: Pod Logs (Filtered by Errors)"
            "□ View: Pod Logs (Unfiltered)"
            "□ View: Deployment YAML"
            "□ View: All Resources in Namespace"
            "↑ Go Home"
        )

        local selected_action
        selected_action=$(printf "%s\n" "${options[@]}" \
            | fzf \
                --prompt="Main Menu ❯ Troubleshooting Tools ❯ " \
                --border=rounded \
                --height=50% \
                --border-label="[KD] Kubernetes doctor [KD]" \
                --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || return

        case "$selected_action" in
            *"Go Back") return 0 ;;
            *"Go Home") menu::select_main_action ;;
            *"Diagnose: Pod Restart Issues" | *"> Diagnose: Pod Restart Issues")
                troubleshooting_pod_restarts || true
                ;;
            *"Diagnose: Network Connectivity" | *"> Diagnose: Network Connectivity")
                menu::troubleshooting_network_tools
                ;;
            *"Diagnose: Pod Issues" | *"> Diagnose: Pod Issues")
                diagnose_pod_issues || true
                ;;
            *"View: Pods by Status" | *"□ View: Pods by Status")
                get_pods_list_by_status || true
                ;;
            *"View: Pod Logs (Smart)" | *"□ View: Pod Logs (Smart)")
                get_pod_logs_smart || true
                ;;
            *"View: Pod Logs (Filtered by Errors)" | *"□ View: Pod Logs (Filtered by Errors)")
                get_logs_with_error_filtering || true
                ;;
            *"View: Pod Logs (Unfiltered)" | *"□ View: Pod Logs (Unfiltered)")
                get_logs_without_error_filtering || true
                ;;
            *"View: Deployment YAML" | *"□ View: Deployment YAML")
                kube_view_deployment_yaml || true
                ;;
            *"View: All Resources in Namespace" | *"□ View: All Resources in Namespace")
                display_all_resources_of_namespace || true
                ;;
            *)
                frame_message "$RED" "❌ Invalid option selected. Try again."
                ;;
        esac
    done
}

# Network Tools Submenu
menu::troubleshooting_network_tools() {
    while true; do
        local tools=(
            "← Go Back"
            "> Tools: Run curl in Pod/Namespace"
            "> Tools: Run ping in Pod/Namespace"
            "> Tools: Run wget in Pod/Namespace"
            "> Tools: Run telnet in Pod/Namespace"
            "> Tools: Run nslookup in Pod/Namespace"
            "↑ Go Home"
        )

        local selected
        selected=$(printf "%s\n" "${tools[@]}" \
            | fzf \
                --prompt="Troubleshooting ❯ Network Tools ❯ " \
                --border=rounded \
                --height=40% \
                --border-label="[KD] Kubernetes doctor [KD]" \
                --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || return

        case "$selected" in
            *"Go Back") return 0 ;;
            *"Go Home") menu::select_main_action ;;
            *"Tools: Run curl" | *"> Tools: Run curl in Pod/Namespace") troubleshooting_run_curl || true ;;
            *"Tools: Run ping" | *"> Tools: Run ping in Pod/Namespace") troubleshooting_run_ping || true ;;
            *"Tools: Run wget" | *"> Tools: Run wget in Pod/Namespace") troubleshooting_run_wget || true ;;
            *"Tools: Run telnet" | *"> Tools: Run telnet in Pod/Namespace") troubleshooting_run_telnet || true ;;
            *"Tools: Run nslookup" | *"> Tools: Run nslookup in Pod/Namespace") troubleshooting_run_nslookup || true ;;
        esac
    done
}
