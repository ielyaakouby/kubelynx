#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
menu::select_main_action() {
    while true; do
        local options=(
            "× Exit"
            "⚙ Kubernetes Core Actions"
            "+ Resource Info & Inspect"
            "? Monitoring & Usage"
            "> Troubleshooting Tools"
            "≡ View & Describe Resources"
            "# Fix a Namespace"
        )

        local selected_action
        selected_action=$(printf "%s\n" "${options[@]}" \
            | fzf \
                --prompt="Main Menu ❯ " \
                --border=rounded \
                --height=11 \
                --no-mouse \
                --border-label="🩺 KubeLynx 🩺" \
                --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || {
            # User cancelled fzf (ESC), exit gracefully
            return 0
        }

        [[ -z "$selected_action" ]] && frame_message "$RED" "❌ No selection made. Try again." && continue

        case "$selected_action" in
            *"Exit")
                break
                ;;
            *"Kubernetes Core Actions")
                submenu_core_k8s_actions
                ;;
            *"Resource Info & Inspect")
                resource_info_and_inspect
                ;;
            *"Monitoring & Usage")
                select_monitor_menu
                ;;
            *"Troubleshooting Tools")
                select_troubleshooting_menu
                ;;
            *"View & Describe Resources")
                submenu_view_and_describe_resources
                ;;
            *"Fix a Namespace")
                local NAMESPACE
                NAMESPACE=$(select_namespace) || return
                set_default_namespace "$NAMESPACE"
                ;;
            *)
                frame_message "$RED" "❌ Invalid option selected. Try again."
                ;;
        esac

        print_separator
    done
}

submenu_core_k8s_actions() {
    local options=(
        "← Go Back"
        "↻ Restart Deployment"
        "⇪ Scale Deployment"
        "⟳ Rollout History"
        "<< Rollback Deployment"
        "→ Port Forward to Bakend"
        "→ Connect to Pod"
        "↑ Go Home"
    )

    local selected_action
    selected_action=$(printf "%s\n" "${options[@]}" \
        | fzf \
            --prompt="Main Menu ❯ K8s Core ❯ " \
            --border=rounded \
            --height=33% \
            --border-label="🔬 KubeLynx" \
            --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow")

    case "$selected_action" in
        *"Go Back") return 0 ;;
        *"Go Home") menu::select_main_action ;;
        *"Restart Deployment") kube_restart_deployment ;;
        *"Scale Deployment") kube_scale_deployment ;;
        *"Rollout History") kube_rollout_history ;;
        *"Rollback Deployment") kube_rollback_deployment ;;
        *"Port Forward to Bakend") kube_port_forward ;;
        *"Connect to Pod") kube_connect_to_pod ;;
    esac
}

####
submenu_view_and_describe_resources() {
    local choice
    local options=(
        "← Go Back"
        "≣ Show Resource YAML"
        "? Describe Resource"
        "↑ Go Home"
    )

    local selected_action
    selected_action=$(printf "%s\n" "${options[@]}" \
        | fzf \
            --prompt="Main Menu ❯ View & Describe ❯ " \
            --border=rounded \
            --height=10% \
            --border-label="🔬 KubeLynx" \
            --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow")

    case "$selected_action" in
        *"Go Back") return 0 ;;
        *"Go Home") menu::select_main_action ;;
        *"Show Resource YAML") show_yaml_resource ;;
        *"Describe Resource") select_describe_resource_menu ;;
    esac
}

resource_info_and_inspect() {
    while true; do
        local options=(
            "← Go Back"
            "[I] Ingress Info"
            "[P] Pod Info"
            "[C] Config & Secrets"
            "[K] Cluster Info"
            "[N] Namespace & Labels"
            "↑ Go Home"
        )
        local choice
        choice=$(printf "%s\n" "${options[@]}" | fzf --prompt="Main Menu ❯ " --border=rounded --no-mouse --border-label="🔬 KubeLynx" --height="11" --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || exit 0

        case "$choice" in
            *"Go Back") return 0 ;;
            *"Go Home") menu::select_main_action ;;
            *"Ingress Info") show_ingress_menu ;;
            *"Pod Info") show_pod_menu ;;
            *"Config & Secrets") show_config_and_secret_menu ;;
            *"Cluster Info") show_cluster_menu ;;
            *"Namespace & Labels") show_namespace_menu ;;
        esac
    done
}

#show_pod_menu() {
#View Pod Events
#View Pod YAML"
show_ingress_menu() {
    generic_submenu "Ingress Info" "9" \
        "← Go Back" \
        "> List Ingresses" \
        "? Describe Ingress" \
        "+ Get Ingress URLs" \
        "↑ Go Home"
}

show_pod_menu() {
    generic_submenu "Pod Info" "9" \
        "← Go Back" \
        "> List Pods" \
        "? Describe Pod" \
        "+ Get Pod Logs" \
        "↑ Go Home"
}

show_config_and_secret_menu() {
    generic_submenu "Config & Secrets"c
    "← Go Back" \
        "> List ConfigMaps" \
        "> List Secrets" \
        "? Describe ConfigMap" \
        "? Describe Secret" \
        "↑ Go Home"
}

show_cluster_menu() {
    generic_submenu "Cluster Info" "9" \
        "← Go Back" \
        "ℹ Cluster Info" \
        "> API Resources" \
        "> Nodes Info" \
        "↑ Go Home"
}

show_namespace_menu() {
    generic_submenu "Namespace & Labels" "10" \
        "← Go Back" \
        "> List Namespaces" \
        "> List Namespace Labels" \
        "? Describe Namespace" \
        "+ Set Namespace" \
        "↑ Go Home"
}

generic_submenu() {
    local title="$1"
    local height="${2:-32%}"
    shift 2
    local options=("$@")

    while true; do
        local choice
        choice=$(printf "%s\n" "${options[@]}" | fzf --prompt="$title ❯ " --border=rounded --no-mouse --border-label="🔬 KubeLynx" --height="$height" --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || return

        case "$choice" in
            *"List Ingresses") list_ingresses || true ;;
            *"Describe Ingress") describe_ingress || true ;;
            *"Get Ingress URLs") get_ingress_urls || true ;;
            *"List Pods") list_pods || true ;;
            *"Describe Pod") describe_pod || true ;;
            *"Get Pod Logs") get_pod_logs_all || true ;;
            *"List ConfigMaps") list_configmaps || true ;;
            *"List Secrets") list_secrets || true ;;
            *"Describe ConfigMap") describe_configmap || true ;;
            *"Describe Secret") describe_secret || true ;;
            *"Cluster Info") show_cluster_info || true ;;
            *"API Resources") kube_show_api_resources || true ;;
            *"Nodes Info") list_nodes_info || true ;;
            *"List Namespaces") list_namespaces || true ;;
            *"Set Namespace") set_default_namespace || true ;;
            *"Describe Namespace") describe_namespace || true ;;
            *"List Namespace Labels") list_namespace_labels || true ;;
            *"Go Back") return 0 ;;
            *"Go Home") menu::select_main_action ;;
        esac

        print_separator
    done
}
