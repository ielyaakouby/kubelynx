#!/usr/bin/env bash
# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
# shellcheck disable=SC2034  # Arrays used via nameref in menu::show_menu

# ============================================================================
# Enhanced Main Menu
# ============================================================================

menu::select_main_action() {
    while true; do
        # Menu options
        local main_options=(
            "Kubernetes Core Actions"
            "Resource Info & Inspect"
            "Monitoring & Usage"
            "Troubleshooting Tools"
            "View & Describe Resources"
            "Fix a Namespace"
            "Exit"
        )

        # Menu descriptions
        local main_descriptions=(
            "Manage deployments, scale, rollback, port forward, and connect to pods"
            "Explore and inspect Kubernetes resources"
            "Monitor cluster usage, pod metrics, and resource allocation"
            "Diagnose and troubleshoot cluster issues"
            "View YAML configurations and describe resources"
            "Set default namespace for kubectl commands"
            "Exit the application"
        )

        # Show menu
        local selected
        selected=$(menu::show_menu \
            "Main Menu" \
            "main_options" \
            "main_descriptions" \
            "Main Menu")

        # Trim whitespace and check if empty
        selected=$(echo "$selected" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$selected" ]] && continue

        # Handle selection
        case "$selected" in
            "Kubernetes Core Actions")
                menu::kubernetes_core_actions
                ;;
            "Resource Info & Inspect")
                resource_info_and_inspect
                ;;
            "Monitoring & Usage")
                select_monitor_menu
                ;;
            "Troubleshooting Tools")
                select_troubleshooting_menu
                ;;
            "View & Describe Resources")
                submenu_view_and_describe_resources
                ;;
            "Fix a Namespace")
                local NAMESPACE
                NAMESPACE=$(select_namespace) || continue
                set_default_namespace "$NAMESPACE"
                ;;
            "Exit")
                //echo -e "${MENU_GREEN}Goodbye!${MENU_RESET}"
                break
                ;;
            *)
                echo -e "${MENU_RED}Invalid option selected.${MENU_RESET}"
                ;;
        esac

        menu::print_separator
    done
}

# ============================================================================
# Enhanced Kubernetes Core Actions Menu
# ============================================================================

menu::kubernetes_core_actions() {
    while true; do
        # Menu options
        local core_options=(
            "Go Back"
            "Restart Deployment"
            "Scale Deployment"
            "Rollout History"
            "Rollback Deployment"
            "Port Forward"
            "Connect to Pod"
            "Go Home"
        )

        # Menu descriptions
        local core_descriptions=(
            "Return to previous menu"
            "Trigger rolling restart of a deployment"
            "Increase or decrease the number of replicas"
            "Show previous rollout revisions and changes"
            "Revert deployment to a previous revision"
            "Forward a pod port to localhost"
            "Open an interactive shell inside a pod"
            "Return to main menu"
        )

        # Confirmation flags (true = requires confirmation)
        local core_confirm=(
            "false"
            "true"  # Restart Deployment
            "true"  # Scale Deployment
            "false" # Rollout History
            "true"  # Rollback Deployment
            "false" # Port Forward
            "false" # Connect to Pod
            "false" # Go Home
        )

        # Show menu
        local selected
        selected=$(menu::show_menu \
            "Kubernetes Core Actions" \
            "core_options" \
            "core_descriptions" \
            "Main Menu > Kubernetes Core Actions" \
            "core_confirm")

        # Trim whitespace and check if empty
        selected=$(echo "$selected" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$selected" ]] && return 0

        # Handle selection
        case "$selected" in
            "Go Back")
                return 0
                ;;
            "Go Home")
                menu::select_main_action
                return 0
                ;;
            "Restart Deployment")
                kube_restart_deployment || true
                ;;
            "Scale Deployment")
                kube_scale_deployment || true
                ;;
            "Rollout History")
                kube_rollout_history || true
                ;;
            "Rollback Deployment")
                kube_rollback_deployment || true
                ;;
            "Port Forward")
                kube_port_forward || true
                ;;
            "Connect to Pod")
                kube_connect_to_pod || true
                ;;
            *)
                echo -e "${MENU_RED}Invalid option selected.${MENU_RESET}"
                ;;
        esac

        menu::print_separator
    done
}
