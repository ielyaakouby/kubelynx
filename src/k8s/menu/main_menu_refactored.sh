#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
menu::select_main_action() {
    while true; do
        local options=(
            "⚙ Kubernetes Core Actions"
            "+ Resource Explorer & Inspect"
            "? Monitoring & Usage"
            "> Troubleshooting Tools"
            "× Exit"
        )

        local selected_action
        selected_action=$(printf "%s\n" "${options[@]}" \
            | fzf \
                --prompt="Main Menu ❯ " \
                --border=rounded \
                --no-mouse \
                --height=27 \
                --border-label="[KD] Kubernetes doctor [KD]" \
                --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow")

        [[ -z "$selected_action" ]] && frame_message "$RED" "❌ No selection made. Try again." && continue

        case "$selected_action" in
            "⚙ Kubernetes Core Actions")
                menu::kubernetes_core_actions
                ;;
            "+ Resource Explorer & Inspect")
                menu::resource_explorer
                ;;
            "? Monitoring & Usage")
                menu::monitoring_menu
                ;;
            "> Troubleshooting Tools")
                menu::troubleshooting_menu
                ;;
            "× Exit")
                break
                ;;
            *)
                frame_message "$RED" "❌ Invalid option selected. Try again."
                ;;
        esac

        print_separator
    done
}

# ============================================================================
# Kubernetes Core Actions Menu
# ============================================================================

menu::kubernetes_core_actions() {
    local options=(
        "← Go Back"
        "Manage: Restart Deployment"
        "Manage: Scale Deployment"
        "View: Rollout History"
        "Manage: Rollback Deployment"
        "Manage: Port Forward"
        "Manage: Connect to Pod"
        "↑ Go Home"
    )

    local selected_action
    selected_action=$(printf "%s\n" "${options[@]}" \
        | fzf \
            --prompt="Main Menu ❯ Kubernetes Core Actions ❯ " \
            --border=rounded \
            --no-mouse \
            --height=33% \
            --border-label="[KD] Kubernetes doctor [KD]" \
            --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || return

    case "$selected_action" in
        *"Go Back") return 0 ;;
        *"Go Home") menu::select_main_action ;;
        *"Restart Deployment") kube_restart_deployment || true ;;
        *"Scale Deployment") kube_scale_deployment || true ;;
        *"Rollout History") kube_rollout_history || true ;;
        *"Rollback Deployment") kube_rollback_deployment || true ;;
        *"Port Forward") kube_port_forward || true ;;
        *"Connect to Pod") kube_connect_to_pod || true ;;
    esac
}

# ============================================================================
# Resource Explorer & Inspect Menu (Merged from "Resource Info & Inspect" + "View & Describe Resources")
# ============================================================================

menu::resource_explorer() {
    while true; do
        local options=(
            "← Go Back"
            "[P] Pods"
            "[N] Services & Ingress"
            "[C] ConfigMaps & Secrets"
            "[NS] Namespaces"
            "[ℹ] Cluster Info"
            "[W] Workloads (Deployments, StatefulSets, DaemonSets)"
            "[S] Storage (PV/PVC)"
            "[G] Generic Tools"
            "↑ Go Home"
        )

        local choice
        choice=$(printf "%s\n" "${options[@]}" \
            | fzf --prompt="Main Menu ❯ Resource Explorer ❯ " \
                --border=rounded \
                --no-mouse \
                --border-label="[KD] Kubernetes doctor [KD]" \
                --height=40% \
                --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || return

        case "$choice" in
            *"Go Back") return 0 ;;
            *"Go Home") menu::select_main_action ;;
            *"Pods") menu::resource_explorer_pods ;;
            *"Services & Ingress") menu::resource_explorer_services_ingress ;;
            *"ConfigMaps & Secrets") menu::resource_explorer_config_secrets ;;
            *"Namespaces") menu::resource_explorer_namespaces ;;
            *"Cluster Info") menu::resource_explorer_cluster ;;
            *"Workloads") menu::resource_explorer_workloads ;;
            *"Storage") menu::resource_explorer_storage ;;
            *"Generic Tools") menu::resource_explorer_generic ;;
        esac
    done
}

# Pods Submenu
menu::resource_explorer_pods() {
    local options=(
        "← Go Back"
        "View: List Pods"
        "Describe: Pod"
        "View: Pod Logs"
        "Inspect: Pod Logs (Errors)"
        "Inspect: Pod Logs (Warnings)"
        "Inspect: Pod Logs (Custom Pattern)"
        "Inspect: Pod Labels"
        "Inspect: Pod Image Versions"
        "Inspect: Pod Replica Count"
        "Inspect: Pod Corresponding Service"
        "View: Pod Resource Limits/Requests"
        "View: Pod Liveness/Readiness Probes"
        "View: Pod YAML"
        "Manage: Execute Command in Pod"
        "Manage: Copy Files from/to Pod"
        "↑ Go Home"
    )

    local choice
    choice=$(printf "%s\n" "${options[@]}" \
        | fzf --prompt="Resource Explorer ❯ Pods ❯ " \
            --border=rounded \
            --no-mouse \
            --border-label="[KD] Kubernetes doctor [KD]" \
            --height=50% \
            --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || return

    case "$choice" in
        *"Go Back") return 0 ;;
        *"Go Home") menu::select_main_action ;;
        *"List Pods") list_pods || true ;;
        *"Describe: Pod") describe_pod || true ;;
        *"Pod Logs" | *"View: Pod Logs") get_pod_logs_all || true ;;
        *"Pod Logs (Errors)" | *"Inspect: Pod Logs (Errors)") get_pod_logs_errors || true ;;
        *"Pod Logs (Warnings)" | *"Inspect: Pod Logs (Warnings)") get_pod_logs_warnings || true ;;
        *"Pod Logs (Custom Pattern)" | *"Inspect: Pod Logs (Custom Pattern)") get_pod_logs_pattern || true ;;
        *"Pod Labels" | *"Inspect: Pod Labels") new_get_pod_labels || true ;;
        *"Image Versions" | *"Inspect: Pod Image Versions") new_get_pods_docker_image_versions || true ;;
        *"Replica Count" | *"Inspect: Pod Replica Count") new_get_pods_replica_count || true ;;
        *"Corresponding Service" | *"Inspect: Pod Corresponding Service") get_pods_corresponding_service || true ;;
        *"Resource Limits/Requests" | *"View: Pod Resource Limits/Requests")
            output=$(get_limit_request_resources_pod)
            print_separator
            echo -e "${GREEN}Resource Limits/Requests:${NC}\n$output" || true
            ;;
        *"Liveness/Readiness Probes" | *"View: Pod Liveness/Readiness Probes")
            output=$(get_liveness_readiness_pod)
            print_separator
            echo -e "${GREEN}Liveness/Readiness Probes:${NC}\n$output" || true
            ;;
        *"Pod YAML" | *"View: Pod YAML") kubectl_get_pod_config || true ;;
        *"Execute Command in Pod" | *"Manage: Execute Command in Pod") ok_kubectl_exec_pod || true ;;
        *"Copy Files from/to Pod" | *"Manage: Copy Files from/to Pod") ok_kubectl_cp_pod || true ;;
    esac
}

# Services & Ingress Submenu
menu::resource_explorer_services_ingress() {
    local options=(
        "← Go Back"
        "View: List Ingresses"
        "Describe: Ingress"
        "View: Ingress URLs"
        "Inspect: Ingress (All)"
        "Inspect: Ingress (by Namespace + Name)"
        "Inspect: Ingress (by URL/Host)"
        "View: List Services"
        "Describe: Service"
        "View: Service YAML"
        "↑ Go Home"
    )

    local choice
    choice=$(printf "%s\n" "${options[@]}" \
        | fzf --prompt="Resource Explorer ❯ Services & Ingress ❯ " \
            --border=rounded \
            --no-mouse \
            --border-label="[KD] Kubernetes doctor [KD]" \
            --height=40% \
            --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || return

    case "$choice" in
        *"Go Back") return 0 ;;
        *"Go Home") menu::select_main_action ;;
        *"List Ingresses" | *"View: List Ingresses") list_ingresses || true ;;
        *"Describe: Ingress") describe_ingress || true ;;
        *"Ingress URLs" | *"View: Ingress URLs") get_ingress_urls || true ;;
        *"Ingress (All)" | *"Inspect: Ingress (All)") ok_kget_ingress_info all || true ;;
        *"Ingress (by Namespace + Name)" | *"Inspect: Ingress (by Namespace + Name)")
            ensure_ingresse_and_namespace || return 1
            ok_kget_ingress_info "$NAMESPACE" "$INGRESSE_NAME" || true
            ;;
        *"Ingress (by URL/Host)" | *"Inspect: Ingress (by URL/Host)")
            read -p "Enter the ingress URL: " ingress_url_O
            ingress_url=$(echo "$ingress_url_O" | sed -E 's|https?://||;s|/$||')
            [[ -z $ingress_url ]] && ingress_url="$(ok_select_ingress all)"
            ok_kget_ingress_info url "$ingress_url" || true
            ;;
        *"List Services" | *"View: List Services")
            # Need to implement list_services function or use kubectl directly
            NAMESPACE=$(select_namespace) || return 1
            if [[ "$NAMESPACE" == "all" ]]; then
                kubectl get services --all-namespaces || true
            else
                kubectl get services -n "$NAMESPACE" || true
            fi
            ;;
        *"Describe: Service") kubectl_describe_service_config || true ;;
        *"Service YAML" | *"View: Service YAML") kubectl_get_svc_config || true ;;
    esac
}

# ConfigMaps & Secrets Submenu
menu::resource_explorer_config_secrets() {
    local options=(
        "← Go Back"
        "View: List ConfigMaps"
        "View: List Secrets"
        "Describe: ConfigMap"
        "Describe: Secret"
        "Inspect: ConfigMap Content"
        "Inspect: Secret Content"
        "View: ConfigMap YAML"
        "View: Secret YAML"
        "↑ Go Home"
    )

    local choice
    choice=$(printf "%s\n" "${options[@]}" \
        | fzf --prompt="Resource Explorer ❯ ConfigMaps & Secrets ❯ " \
            --border=rounded \
            --no-mouse \
            --border-label="[KD] Kubernetes doctor [KD]" \
            --height=40% \
            --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || return

    case "$choice" in
        *"Go Back") return 0 ;;
        *"Go Home") menu::select_main_action ;;
        *"List ConfigMaps" | *"View: List ConfigMaps") list_configmaps || true ;;
        *"List Secrets" | *"View: List Secrets") list_secrets || true ;;
        *"Describe: ConfigMap") describe_configmap || true ;;
        *"Describe: Secret") describe_secret || true ;;
        *"ConfigMap Content" | *"Inspect: ConfigMap Content") display_configmap_content || true ;;
        *"Secret Content" | *"Inspect: Secret Content") display_secret_content || true ;;
        *"ConfigMap YAML" | *"View: ConfigMap YAML") kubectl_get_configmap_config || true ;;
        *"Secret YAML" | *"View: Secret YAML")
            # Need to implement or use describe
            describe_secret || true
            ;;
    esac
}

# Namespaces Submenu (includes Fix a Namespace)
menu::resource_explorer_namespaces() {
    local options=(
        "← Go Back"
        "View: List Namespaces"
        "View: Namespace Labels"
        "Describe: Namespace"
        "Fix: Set Default Namespace"
        "↑ Go Home"
    )

    local choice
    choice=$(printf "%s\n" "${options[@]}" \
        | fzf --prompt="Resource Explorer ❯ Namespaces ❯ " \
            --border=rounded \
            --no-mouse \
            --border-label="[KD] Kubernetes doctor [KD]" \
            --height=32% \
            --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || return

    case "$choice" in
        *"Go Back") return 0 ;;
        *"Go Home") menu::select_main_action ;;
        *"List Namespaces" | *"View: List Namespaces") list_namespaces || true ;;
        *"Namespace Labels" | *"View: Namespace Labels") list_namespace_labels || true ;;
        *"Describe: Namespace") describe_namespace || true ;;
        *"Set Default Namespace" | *"Fix: Set Default Namespace")
            local NAMESPACE
            NAMESPACE=$(select_namespace) || return 1
            set_default_namespace "$NAMESPACE" || true
            ;;
    esac
}

# Cluster Info Submenu
menu::resource_explorer_cluster() {
    local options=(
        "← Go Back"
        "View: Cluster Info"
        "View: API Resources"
        "View: Nodes Info"
        "View: Nodes List (by Age)"
        "Inspect: Count All Resources"
        "↑ Go Home"
    )

    local choice
    choice=$(printf "%s\n" "${options[@]}" \
        | fzf --prompt="Resource Explorer ❯ Cluster Info ❯ " \
            --border=rounded \
            --no-mouse \
            --border-label="[KD] Kubernetes doctor [KD]" \
            --height=32% \
            --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || return

    case "$choice" in
        *"Go Back") return 0 ;;
        *"Go Home") menu::select_main_action ;;
        *"Cluster Info" | *"View: Cluster Info") show_cluster_info || true ;;
        *"API Resources" | *"View: API Resources") kube_show_api_resources || true ;;
        *"Nodes Info" | *"View: Nodes Info") list_nodes_info || true ;;
        *"Nodes List (by Age)" | *"View: Nodes List (by Age)") get_nodes_list_sort_by_age || true ;;
        *"Count All Resources" | *"Inspect: Count All Resources") new_count_resource_types || true ;;
    esac
}

# Workloads Submenu (Deployments, StatefulSets, DaemonSets)
menu::resource_explorer_workloads() {
    local options=(
        "← Go Back"
        "View: List Deployments"
        "Describe: Deployment"
        "View: Deployment YAML"
        "View: List StatefulSets"
        "Describe: StatefulSet"
        "View: StatefulSet YAML"
        "View: List DaemonSets"
        "Describe: DaemonSet"
        "View: DaemonSet YAML"
        "↑ Go Home"
    )

    local choice
    choice=$(printf "%s\n" "${options[@]}" \
        | fzf --prompt="Resource Explorer ❯ Workloads ❯ " \
            --border=rounded \
            --no-mouse \
            --border-label="[KD] Kubernetes doctor [KD]" \
            --height=40% \
            --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || return

    case "$choice" in
        *"Go Back") return 0 ;;
        *"Go Home") menu::select_main_action ;;
        *"List Deployments" | *"View: List Deployments")
            NAMESPACE=$(select_namespace) || return 1
            if [[ "$NAMESPACE" == "all" ]]; then
                kubectl get deployments --all-namespaces || true
            else
                kubectl get deployments -n "$NAMESPACE" || true
            fi
            ;;
        *"Describe: Deployment") kubectl_describe_deployment_config || true ;;
        *"Deployment YAML" | *"View: Deployment YAML") kubectl_get_deployment_config || true ;;
        *"List StatefulSets" | *"View: List StatefulSets")
            NAMESPACE=$(select_namespace) || return 1
            if [[ "$NAMESPACE" == "all" ]]; then
                kubectl get statefulsets --all-namespaces || true
            else
                kubectl get statefulsets -n "$NAMESPACE" || true
            fi
            ;;
        *"Describe: StatefulSet") kubectl_describe_statefulset_config || true ;;
        *"StatefulSet YAML" | *"View: StatefulSet YAML") kubectl_get_statefulsets_config || true ;;
        *"List DaemonSets" | *"View: List DaemonSets")
            NAMESPACE=$(select_namespace) || return 1
            if [[ "$NAMESPACE" == "all" ]]; then
                kubectl get daemonsets --all-namespaces || true
            else
                kubectl get daemonsets -n "$NAMESPACE" || true
            fi
            ;;
        *"Describe: DaemonSet") kubectl_describe_daemonset_config || true ;;
        *"DaemonSet YAML" | *"View: DaemonSet YAML") kubectl_get_daemonset_config || true ;;
    esac
}

# Storage Submenu (PV/PVC)
menu::resource_explorer_storage() {
    local options=(
        "← Go Back"
        "View: PersistentVolume Info"
        "View: PersistentVolumeClaim Info"
        "↑ Go Home"
    )

    local choice
    choice=$(printf "%s\n" "${options[@]}" \
        | fzf --prompt="Resource Explorer ❯ Storage ❯ " \
            --border=rounded \
            --no-mouse \
            --border-label="[KD] Kubernetes doctor [KD]" \
            --height=20% \
            --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || return

    case "$choice" in
        *"Go Back") return 0 ;;
        *"Go Home") menu::select_main_action ;;
        *"PersistentVolume Info" | *"View: PersistentVolume Info") kget_pv_info || true ;;
        *"PersistentVolumeClaim Info" | *"View: PersistentVolumeClaim Info") kget_pvc_info || true ;;
    esac
}

# Generic Tools Submenu (from "View & Describe Resources")
menu::resource_explorer_generic() {
    local options=(
        "← Go Back"
        "View: Resource YAML (Any)"
        "Describe: Pod"
        "Describe: Service"
        "Describe: Ingress"
        "Describe: Deployment"
        "Describe: StatefulSet"
        "Describe: DaemonSet"
        "Describe: Node"
        "Describe: Other Resources"
        "↑ Go Home"
    )

    local choice
    choice=$(printf "%s\n" "${options[@]}" \
        | fzf --prompt="Resource Explorer ❯ Generic Tools ❯ " \
            --border=rounded \
            --no-mouse \
            --border-label="[KD] Kubernetes doctor [KD]" \
            --height=50% \
            --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || return

    case "$choice" in
        *"Go Back") return 0 ;;
        *"Go Home") menu::select_main_action ;;
        *"Resource YAML (Any)" | *"View: Resource YAML (Any)") show_yaml_resource || true ;;
        *"Describe: Pod") kubectl_describe_pod_config && print_separator || true ;;
        *"Describe: Service") kubectl_describe_service_config && print_separator || true ;;
        *"Describe: Ingress") kubectl_describe_ingress_config && print_separator || true ;;
        *"Describe: Deployment") kubectl_describe_deployment_config && print_separator || true ;;
        *"Describe: StatefulSet") kubectl_describe_statefulset_config && print_separator || true ;;
        *"Describe: DaemonSet") kubectl_describe_daemonset_config && print_separator || true ;;
        *"Describe: Node") kubectl_describe_node_config && print_separator || true ;;
        *"Describe: Other Resources" | *"Describe: Other Resources") kubectl_describe_any && print_separator || true ;;
    esac
}

# Alias for missing function
kube_view_deployment_yaml() {
    kubectl_get_deployment_config "$@"
}

# Alias for typo function
Rellout_resource() {
    kube_restart_resource "$@"
}

# Keyboard shortcuts
