#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
function troubleshooting_pod_restarts() {

    if [ -z "${1:-}" ]; then
        echo -e "\n${CYAN}🔄 Checking for pods with restarts...${RESET}"

        local namespace_options=(
            "← Go Back"
            "↪ All namespaces"
            "↪ Specific namespace"
        )

        local namespace_choice
        namespace_choice=$(printf "%s\n" "${namespace_options[@]}" \
            | fzf --prompt="Check pods in > " \
                --height=10 \
                --border=rounded \
                --no-mouse \
                --border-label="🩺 Kubernetes doctor 🩺" \
                --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || {
            echo -e "\n${YELLOW}No selection made. Exiting...${RESET}\n"
            return 1
        }

        if [[ "$namespace_choice" == "← Go Back" ]]; then
            return 0
        elif [[ "$namespace_choice" == "↪ All namespaces" ]]; then
            NAMESPACE=""
        elif [[ "$namespace_choice" == "↪ Specific namespace" ]]; then
            NAMESPACE=$(select_namespace) || {
                echo -e "\n${YELLOW}No namespace selected. Exiting...${RESET}\n"
                return 1
            }
        else
            echo -e "\n${YELLOW}Invalid selection. Exiting...${RESET}\n"
            return 1
        fi
    else
        NAMESPACE="$1"
        echo -e "\n${CYAN}🔄 Checking for pods with restarts...${RESET}"
        echo -e "${CYAN}Checking in namespace: $NAMESPACE${RESET}\n"
    fi

    # Collect pods with restarts
    if [ -z "$NAMESPACE" ]; then
        pods_with_restarts=$(kubectl get pods --all-namespaces -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,RESTARTS:.status.containerStatuses[*].restartCount" --no-headers 2>/dev/null \
            | while read -r namespace name restarts; do
                if [ -n "$restarts" ]; then
                    sum=$(echo "$restarts" | tr ',' '+' | bc 2>/dev/null || echo "0")
                    if [ "$sum" -gt 0 ] 2>/dev/null; then
                        printf "%-30s %-60s %-10s\n" "$namespace" "$name" "$sum"
                    fi
                fi
            done | sort -k3,3n)
    else
        pods_with_restarts=$(kubectl get pods -n "$NAMESPACE" -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,RESTARTS:.status.containerStatuses[*].restartCount" --no-headers 2>/dev/null \
            | while read -r namespace name restarts; do
                if [ -n "$restarts" ]; then
                    sum=$(echo "$restarts" | tr ',' '+' | bc 2>/dev/null || echo "0")
                    if [ "$sum" -gt 0 ] 2>/dev/null; then
                        printf "%-30s %-60s %-10s\n" "$namespace" "$name" "$sum"
                    fi
                fi
            done | sort -k3,3n)
    fi

    # Check if there are any pods with restarts
    if [ -z "$pods_with_restarts" ]; then
        echo -e "\n${GREEN}✅ No pods with restarts found.${RESET}\n"
        return 0
    fi

    # Display summary
    echo ""

    pod_count=$(echo "$pods_with_restarts" | wc -l)
    echo -e "${CYAN}📊 Found ${LIGHT_YELLOW}$pod_count${CYAN} pod(s) with restarts:${RESET}\n"

    # Display pod list in summary format
    while IFS= read -r pod_line; do
        if [ -n "$pod_line" ]; then
            namespace=$(echo "$pod_line" | awk '{print $1}')
            pod_name=$(echo "$pod_line" | awk '{print $2}')
            restart_count=$(echo "$pod_line" | awk '{print $3}')
            echo -e "  ${LIGHT_RED}•${RESET} ${CYAN}$namespace/$pod_name${RESET} - ${LIGHT_RED}$restart_count${RESET} restarts"
        fi
    done <<<"$pods_with_restarts"

    echo ""

    # Ask if user wants to filter to top 10
    if [ "$pod_count" -gt 10 ]; then
        local filter_options=(
            "↪ Process all pods ($pod_count pods)"
            "↪ List only top 10 high restarted pods"
        )

        local filter_choice
        filter_choice=$(printf "%s\n" "${filter_options[@]}" \
            | fzf --prompt="Select processing mode > " \
                --height=10 \
                --border=rounded \
                --no-mouse \
                --border-label="🩺 Kubernetes doctor 🩺" \
                --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || {
            echo -e "\n${YELLOW}No selection made. Processing all pods...${RESET}\n"
            filter_choice="↪ Process all pods ($pod_count pods)"
        }

        if [[ "$filter_choice" == *"top 10"* ]]; then
            print_separator
            echo -e "\n${CYAN}📋 Filtering to top 10 pods with highest restart counts...${RESET}\n"
            pods_with_restarts=$(echo "$pods_with_restarts" | sort -k3,3nr | head -10)
            pod_count=10
            echo -e "${CYAN}📊 Showing top ${LIGHT_YELLOW}$pod_count${CYAN} pod(s) with highest restarts:${RESET}\n"
            # Redisplay the filtered list
            while IFS= read -r pod_line; do
                if [ -n "$pod_line" ]; then
                    namespace=$(echo "$pod_line" | awk '{print $1}')
                    pod_name=$(echo "$pod_line" | awk '{print $2}')
                    restart_count=$(echo "$pod_line" | awk '{print $3}')
                    echo -e "  ${LIGHT_RED}•${RESET} ${CYAN}$namespace/$pod_name${RESET} - ${LIGHT_RED}$restart_count${RESET} restarts"
                fi
            done <<<"$pods_with_restarts"
            echo ""
        fi
    fi

    # Sort by restart count (descending) for processing
    pods_with_restarts_sorted=$(echo "$pods_with_restarts" | sort -k3,3nr)
    IFS=$'\n' read -rd '' -a pod_array <<<"$pods_with_restarts_sorted" || true

    # Process each pod
    for pod_info in "${pod_array[@]}"; do
        if [ -z "$pod_info" ]; then
            continue
        fi

        NAMESPACE=$(echo "$pod_info" | awk '{print $1}')
        pod_name=$(echo "$pod_info" | awk '{print $2}')
        restart_count=$(echo "$pod_info" | awk '{print $3}')

        # Display formatted pod information
        echo -e "${LIGHT_RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo -e "${LIGHT_RED}🔴 Pod: $pod_name (Namespace: $NAMESPACE) - Restarts: $restart_count${RESET}"
        echo -e "${LIGHT_RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo ""

        # Show interactive menu
        while true; do
            local options=(
                "← Go Back"
                "↪ Exit troubleshooting"
                "↪ Skip to next pod"
                "↪ Rollout restart deployment"
                "↪ View pod YAML"
                "↪ View pod logs"
                "↪ Describe pod"
                "↪ Delete this pod"
                "↪ Delete all pods listed"
                "↪ List only top 10 high restarted troubleshooting"
            )

            local action
            action=$(printf "%s\n" "${options[@]}" \
                | fzf --prompt="Action for $pod_name > " \
                    --height=13 \
                    --border=rounded \
                    --no-mouse \
                    --border-label="🩺 Kubernetes doctor 🩺" \
                    --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || {
                # If user cancels fzf, treat as exit
                break
            }

            case "$action" in
                *"Go Back")
                    echo -e "\n${YELLOW}Going back...${RESET}\n"
                    return 0
                    ;;
                *"Exit troubleshooting")
                    #echo -e "\n${YELLOW}Exiting troubleshooting...${RESET}\n"
                    return 0
                    ;;
                *"Skip to next pod")
                    echo -e "\n${CYAN}Skipping to next pod...${RESET}\n"
                    break
                    ;;
                *"Rollout restart deployment")
                    echo ""
                    kube_restart_resource "$pod_name" "$NAMESPACE" || true
                    echo ""
                    ;;
                *"View pod YAML")
                    echo ""
                    kubectl_get_pod_config "$NAMESPACE" "$pod_name" || true
                    echo ""
                    ;;
                *"View pod logs")
                    echo ""
                    get_logs_without_error_filtering "$NAMESPACE" "$pod_name" || true
                    echo ""
                    ;;
                *"Describe pod")
                    echo ""
                    kubectl_describe_pod "$NAMESPACE" "$pod_name" || true
                    echo ""
                    ;;
                *"Delete this pod")
                    echo ""
                    read -r -p "⚠️  Are you sure you want to delete pod '$pod_name' in namespace '$NAMESPACE'? (y/N): " confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        if kubectl -n "$NAMESPACE" delete pod "$pod_name" 2>/dev/null; then
                            echo -e "${GREEN}✅ Pod '$pod_name' deleted successfully.${RESET}"
                        else
                            echo -e "${RED}❌ Failed to delete pod '$pod_name'.${RESET}"
                        fi
                    else
                        echo -e "${YELLOW}Deletion cancelled.${RESET}"
                    fi
                    echo ""
                    ;;
                *"List only top 10 high restarted troubleshooting")
                    echo ""
                    local current_count
                    current_count=$(echo "$pods_with_restarts" | wc -l)
                    if [ "$current_count" -le 10 ]; then
                        echo -e "${YELLOW}⚠️  Already showing $current_count pod(s) or less.${RESET}"
                        echo ""
                    else
                        print_separator
                        echo -e "${CYAN}📋 Filtering to top 10 pods with highest restart counts...${RESET}\n"
                        pods_with_restarts=$(echo "$pods_with_restarts" | sort -k3,3nr | head -10)
                        pod_count=10

                        echo -e "${CYAN}📊 Showing top ${LIGHT_YELLOW}$pod_count${CYAN} pod(s) with highest restarts:${RESET}\n"
                        # Redisplay the filtered list
                        while IFS= read -r pod_line; do
                            if [ -n "$pod_line" ]; then
                                namespace=$(echo "$pod_line" | awk '{print $1}')
                                pod_name=$(echo "$pod_line" | awk '{print $2}')
                                restart_count=$(echo "$pod_line" | awk '{print $3}')
                                echo -e "  ${LIGHT_RED}•${RESET} ${CYAN}$namespace/$pod_name${RESET} - ${LIGHT_RED}$restart_count${RESET} restarts"
                            fi
                        done <<<"$pods_with_restarts"
                        echo ""

                        # Rebuild pod_array with filtered pods
                        pods_with_restarts_sorted=$(echo "$pods_with_restarts" | sort -k3,3nr)
                        IFS=$'\n' read -rd '' -a pod_array <<<"$pods_with_restarts_sorted" || true

                        echo -e "${CYAN}🔄 Restarting troubleshooting with filtered pods...${RESET}\n"

                        # Break out of inner loop and continue with filtered pods
                        break
                    fi
                    ;;
                *"Delete all pods listed")
                    echo ""
                    local total_pods
                    total_pods=$(echo "$pods_with_restarts" | wc -l)
                    read -r -p "⚠️  Are you sure you want to delete ALL $total_pods pod(s) with restarts? This cannot be undone! (y/N): " confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        echo ""
                        local deleted_count=0
                        local failed_count=0
                        local pod_ns pod_n

                        while IFS= read -r pod_line; do
                            if [ -z "$pod_line" ]; then
                                continue
                            fi

                            pod_ns=$(echo "$pod_line" | awk '{print $1}')
                            pod_n=$(echo "$pod_line" | awk '{print $2}')

                            if kubectl -n "$pod_ns" delete pod "$pod_n" 2>/dev/null; then
                                echo -e "${GREEN}✅ Pod '$pod_n' deleted successfully.${RESET}"
                                deleted_count=$((deleted_count + 1))
                            else
                                echo -e "${RED}❌ Failed to delete pod '$pod_n'.${RESET}"
                                failed_count=$((failed_count + 1))
                            fi
                        done <<<"$pods_with_restarts"

                        echo ""
                        echo -e "${CYAN}📊 Summary: ${GREEN}$deleted_count${CYAN} deleted, ${RED}$failed_count${CYAN} failed${RESET}"
                        echo ""
                        # Exit the function after deleting all pods
                        return 0
                    else
                        echo -e "${YELLOW}Deletion cancelled.${RESET}"
                        echo ""
                    fi
                    ;;
                *)
                    echo -e "${YELLOW}Unknown action.${RESET}"
                    ;;
            esac
        done
    done

    echo -e "\n${GREEN}✅ Finished processing all pods with restarts.${RESET}\n"
}

pod_restarted_select_other_action() {
    namespace="$1"
    POD_NAME="$2"
    actions=(
        "Delete pod $POD_NAME"
        "Describe pod $POD_NAME"
        "Get config of pod $POD_NAME"
        "Get log of pod $POD_NAME"
        "View Pod Logs (Filtered by Errors) of pod $POD_NAME"
        "View Pod Logs (Unfiltered) of pod $POD_NAME"
    )

    action=$(printf "%s\n" "${actions[@]}" | fzf --header "Select an action:")

    case "$action" in
        "Describe pod $POD_NAME")
            kubectl_describe_pod "$namespace" "$POD_NAME"
            print_separator
            ;;
        "Get config of pod $POD_NAME")
            kubectl_get_pod_config "$namespace" "$POD_NAME"
            print_separator
            ;;
        "Get log of pod $POD_NAME")
            get_logs_without_error_filtering_ "$namespace" "$POD_NAME"
            print_separator
            ;;
        "View Pod Logs (Filtered by Errors) of pod $POD_NAME")
            get_logs_with_error_filtering "$namespace" "$POD_NAME"
            print_separator
            ;;
        "View Pod Logs (Unfiltered) of pod $POD_NAME")
            echo "get_logs_without_error_filtering $namespace $POD_NAME"
            get_logs_without_error_filtering "$namespace" "$POD_NAME"
            print_separator
            ;;
        *)
            echo -e "${LIGHT_RED}No action selected.${RESET}"
            ;;
    esac
}
