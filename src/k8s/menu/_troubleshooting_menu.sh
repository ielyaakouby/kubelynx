#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
select_troubleshooting_menu() {
    local options=(
        "← Go Back"
        "✚ Pod Restarted Troubleshooting"
        "↪ Network Tools"
        "⚠ Diagnose Pod Issues"
        "🤖 AI Analysis"
        "☰ Get Pods List by Status"
        "→ View Pod Logs"
        "→ View Deployment YAML"
        "↑ Go Home"
    )

    while true; do
        local selected_action
        selected_action=$(printf "%s\n" "${options[@]}" \
            | fzf --prompt="Main Menu ❯ Troubleshooting Menu ❯ " \
                --height=13 \
                --border=rounded \
                --no-mouse \
                --border-label="🩺 Kubernetes doctor 🩺" \
                --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || {
            frame_message "$YELLOW" "[!] No action selected. Returning..."
            return 1
        }

        dispatch_troubleshooting_action "$selected_action" || return
    done
}

dispatch_troubleshooting_action() {
    local action="$1"
    case "$action" in
        "← Go Back") menu::select_main_action ;;
        "↑ Go Home") menu::select_main_action ;;
        "✚ Pod Restarted Troubleshooting") troubleshooting_pod_restarts ;;
        "↪ Network Tools") select_network_tools_menu ;;
        "⚠ Diagnose Pod Issues") diagnose_pod_issues ;;
        "🤖 AI Analysis") ai_analysis::analyze_pod ;;
        "☰ Get Pods List by Status") get_pods_list_by_status ;;
        "→ View Pod Logs") get_pod_logs_smart ;;
        "→ View Deployment YAML") kubectl_get_deployment_config ;;
        *)
            frame_message "$RED" "[!] Invalid option selected."
            ;;
    esac
}

select_network_tools_menu() {
    local tools=(
        "← Go Back"
        "> Run curl in Pod/Namespace"
        "> Run ping in Pod/Namespace"
        "> Run wget in Pod/Namespace"
        "> Run telnet in Pod/Namespace"
        "> Run nslookup in Pod/Namespace"
        "↑ Go Home"
    )

    while true; do
        local selected
        selected=$(printf "%s\n" "${tools[@]}" \
            | fzf --prompt=" Network Tools ❯ " \
                --height=40% --border=rounded \
                --no-mouse \
                --border-label="🩺 Kubernetes doctor 🩺" \
                --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || return

        case "$selected" in
            *"Go Back") return 0 ;;
            *"Go Home") menu::select_main_action ;;
            *"Run curl in Pod/Namespace") troubleshooting_run_curl ;;
            *"Run ping in Pod/Namespace") troubleshooting_run_ping ;;
            *"Run wget in Pod/Namespace") troubleshooting_run_wget ;;
            *"Run telnet in Pod/Namespace") troubleshooting_run_telnet ;;
            *"Run nslookup in Pod/Namespace") troubleshooting_run_nslookup ;;
        esac
    done
}
