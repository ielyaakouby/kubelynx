#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
resource_info_and_inspect_menu_() {
    while true; do
        local options=(
            "← Go Back"
            "☰ Ingress Info"
            "☰ Pod Info"
            "☰ Config & Secrets"
            "☰ Cluster Info"
            "☰ Namespace & Labels"
            "↑ Go Home"
        )

        local selected_action
        selected_action=$(printf "%s\n" "${options[@]}" \
            | fzf --prompt="Main Menu ❯ Kube Info ❯ " \
                --border=rounded \
                --no-mouse \
                --border-label="🩺 Kubernetes doctor 🩺" \
                --height=32% \
                --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow")

        [[ -z "$selected_action" ]] && frame_message "$RED" "No selection made. Try again." && continue

        case "$selected_action" in
            *"Go Back") return 0 ;;
            *"Go Home") menu::select_main_action ;;
            *"Ingress Info") submenu_ingress_info ;;
            *"Pod Info") submenu_pod_info ;;
            *"Config & Secrets") submenu_config_secret ;;
            *"Cluster Info") submenu_cluster_info ;;
            *"Namespace & Labels") submenu_namespace_labels ;;
            *) frame_message "$RED" "Invalid option selected." ;;
        esac
        print_separator
    done
}

submenu_ingress_info() {
    local options=(
        "← Go Back"
        "↪ Ingress: all"
        "↪ Ingress: by namespace + name"
        "↪ Ingress: by URL/host"
    )
    local choice=$(printf "%s\n" "${options[@]}" \
        | fzf --prompt="Main Menu ❯ Kube Info Menu ❯ Ingress Info ❯ " \
            --border=rounded \
            --no-mouse \
            --border-label="🩺 Kubernetes doctor 🩺" \
            --height=32% \
            --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow")

    case "$choice" in
        *"Go Back") return ;;
        *"Ingress: all") ok_kget_ingress_info all ;;
        *"Ingress: by namespace + name")
            ensure_ingresse_and_namespace || return 1
            ok_kget_ingress_info "$NAMESPACE" "$INGRESSE_NAME"
            ;;
        *"Ingress: by URL"*)
            read -p "Enter the ingress URL: " ingress_url_O
            ingress_url=$(echo "$ingress_url_O" | sed -E 's|https?://||;s|/$||')
            [[ -z $ingress_url ]] && ingress_url="$(ok_select_ingress all)"
            ok_kget_ingress_info url "$ingress_url"
            ;;
    esac
}

submenu_pod_info() {
    local options=(
        "← Go Back"
        "✚ Live logs from one pod"
        "✚ Docker image versions"
        "✚ Replica count"
        "✚ Pod's corresponding service"
        "✚ Pod labels"
    )
    local choice=$(printf "%s\n" "${options[@]}" \
        | fzf --prompt="Main Menu ❯ Kube Info Menu ❯ Pod Info ❯ " \
            --border=rounded \
            --no-mouse \
            --border-label="🩺 Kubernetes doctor 🩺" \
            --height=32% \
            --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow")

    case "$choice" in
        *"Go Back") return ;;
        *"Live logs"*) get_pods_live_logs_by_giving_one_pod ;;
        *"Docker image versions"*)
            new_get_pods_docker_image_versions
            echo -e "${GREEN}Selected Pod: $POD_NAME${NC}"
            ;;
        *"Replica count"*)
            new_get_pods_replica_count
            echo -e "${GREEN}Selected Pod: $POD_NAME${NC}"
            ;;
        *"corresponding service"*) get_pods_corresponding_service ;;
        *"Pod labels"*)
            new_get_pod_labels
            echo -e "${GREEN}Selected Pod: $POD_NAME${NC}"
            ;;
    esac
}

submenu_config_secret() {
    local options=(
        "← Go Back"
        "✚ Get configmap content"
        "✚ Get secret content"
    )
    local choice=$(printf "%s\n" "${options[@]}" \
        | fzf --prompt="Main Menu ❯ Kube Info Menu ❯ Config & Secrets ❯ " \
            --border=rounded \
            --no-mouse \
            --border-label="🩺 Kubernetes doctor 🩺" \
            --height=32% \
            --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow")

    case "$choice" in
        *"Go Back") return ;;
        *"configmap"*) display_configmap_content ;;
        *"secret"*) display_secret_content ;;
    esac
}

submenu_cluster_info() {
    while true; do
        local options=(
            "← Go Back"
            "☰ Nodes List (by Age)"
            "☰ Count All Resources"
        )

        local choice
        choice=$(printf "%s\n" "${options[@]}" \
            | fzf --prompt=" 🌟  Main Menu ➔ Kube Info Menu ➔ Cluster Info ➔ " \
                --header="   ➔ Kubernetes Cluster Info - Select an action" \
                --height=50% \
                --border=rounded \
                --border-label="🩺 Kubernetes doctor 🩺" \
                --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow")

        case "$choice" in
            *"Go Back") return ;;
            *"Nodes List"*) get_nodes_list_sort_by_age ;;
            *"Count All"*) new_count_resource_types ;;
            *) frame_message "$RED" "Invalid option selected." ;;
        esac
    done
}

submenu_namespace_labels() {
    while true; do
        local options=(
            "☰ List Namespaces"
            "☰ Describe Namespace"
            "☰ List Namespace Labels"
            "← Go Back"
        )

        local selected
        selected=$(printf "%s\n" "${options[@]}" \
            | fzf --prompt="Namespace & Labels ❯ " --border=rounded --no-mouse --border-label="🩺 Kubernetes doctor 🩺" --height=32% --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow")

        [[ -z "$selected" ]] && frame_message "$RED" "No selection made." && continue

        case "$selected" in
            *"List Namespaces")
                print_separator
                kubectl get namespaces
                ;;

            *"Describe Namespace")
                local ns
                ns=$(select_namespace) || continue
                if [[ "$ns" == "all" ]]; then
                    frame_message "$YELLOW" "⚠️ 'all' is not supported for describing a single namespace."
                    continue
                fi
                print_separator
                kubectl describe namespace "$ns"
                ;;

            *"List Namespace Labels")
                local ns
                ns=$(select_namespace) || continue
                print_separator
                if [[ "$ns" == "all" ]]; then
                    kubectl get namespaces --show-labels
                else
                    kubectl get namespace "$ns" --show-labels
                fi
                ;;

            *"Go Back")
                return
                ;;

            *)
                frame_message "$RED" "Invalid option."
                ;;
        esac

        print_separator
    done
}
