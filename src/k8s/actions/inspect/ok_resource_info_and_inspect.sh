#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
choose_yaml_format() {
    printf "Normal YAML Output\nNeat YAML Output (kubectl-neat)" \
        | fzf --prompt="▶ Select YAML Format: " --height=20%
}

list_ingresses() {
    NAMESPACE=$(select_namespace) || return 1

    if [[ "$NAMESPACE" == "all" ]]; then
        print_separator
        kubectl get ingress --all-namespaces
    else
        check_resource_count ingress "$NAMESPACE" || return
        print_separator
        kubectl get ingress -n "$NAMESPACE"
    fi
}

describe_ingress() {
    NAMESPACE=$(select_namespace) || return 1
    check_resource_count ingress "$NAMESPACE" || return 1

    local ingress
    local prompt="Select Ingress ❯ "

    if [[ "$NAMESPACE" == "all" ]]; then
        ingress=$(kubectl get ingress --all-namespaces --no-headers | awk '{print $1 " (" $1 "/" $2 ")"}' | fzf --prompt="$prompt")
        selected_ns=$(echo "$ingress" | sed -E 's/.*\(([a-z0-9-]+)\/[a-z0-9-]+\).*/\1/')
        ingress_name=$(echo "$ingress" | sed -E 's/.*\([a-z0-9-]+\/([a-z0-9-]+)\).*/\1/')
        [[ -n "$ingress_name" && -n "$selected_ns" ]] && kubectl describe ingress "$ingress_name" -n "$selected_ns"
    else
        ingress=$(kubectl get ingress -n "$NAMESPACE" --no-headers | awk '{print $1}' | fzf --prompt="$prompt")
        [[ -n "$ingress" ]] && kubectl describe ingress "$ingress" -n "$NAMESPACE"
    fi
}

get_ingress_urls() {
    NAMESPACE=$(select_namespace) || return 1
    check_resource_count ingress "$NAMESPACE" || return 1
    print_separator

    if [[ "$NAMESPACE" == "all" ]]; then
        kubectl get ingress --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{" → "}{.spec.rules[*].host}{"\n"}{end}'
    else
        kubectl get ingress -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{" → "}{.spec.rules[*].host}{"\n"}{end}'
    fi
}

list_pods() {
    NAMESPACE=$(select_namespace) || return 1
    check_resource_count pods "$NAMESPACE" || return 1
    print_separator

    if [[ "$NAMESPACE" == "all" ]]; then
        kubectl get pods --all-namespaces
    else
        kubectl get pods -n "$NAMESPACE"
    fi
}

describe_pod() {
    local NAMESPACE pod_name selected_ns

    NAMESPACE=$(select_namespace) || return 1
    check_resource_count pods "$NAMESPACE" || return

    pod_name=$(select_pod "$NAMESPACE") || return 1

    if [[ "$NAMESPACE" == "all" ]]; then
        selected_ns=$(echo "$pod_name" | sed -E 's/.*\(ns:([^)]*)\).*/\1/')
        pod_name=$(echo "$pod_name" | awk '{print $1}')
        [[ -n "$pod_name" && -n "$selected_ns" ]] && kubectl describe pod "$pod_name" -n "$selected_ns"
    else
        kubectl describe pod "$pod_name" -n "$NAMESPACE"
    fi
}

######

list_configmaps() {
    NAMESPACE=$(select_namespace) || return 1
    check_resource_count configmaps "$NAMESPACE" || return 1
    print_separator

    if [[ "$NAMESPACE" == "all" ]]; then
        kubectl get configmaps --all-namespaces
    else
        kubectl get configmaps -n "$NAMESPACE"
    fi
}

describe_configmap() {
    NAMESPACE=$(select_namespace) || return 1
    check_resource_count configmaps "$NAMESPACE" || return 1

    local configmap selected_ns prompt="Select ConfigMap ❯ "

    if [[ "$NAMESPACE" == "all" ]]; then
        configmap=$(kubectl get configmaps --all-namespaces --no-headers | awk '{print $2 " (ns:" $1 ")"}' | fzf --prompt="$prompt")
        selected_ns=$(echo "$configmap" | sed -E 's/.*\(ns:([^)]*)\).*/\1/')
        configmap_name=$(echo "$configmap" | awk '{print $1}')
        [[ -n "$configmap_name" && -n "$selected_ns" ]] && kubectl describe configmap "$configmap_name" -n "$selected_ns"
    else
        configmap=$(kubectl get configmaps -n "$NAMESPACE" --no-headers | awk '{print $1}' | fzf --prompt="$prompt")
        [[ -n "$configmap" ]] && kubectl describe configmap "$configmap" -n "$NAMESPACE"
    fi
}

list_secrets() {
    NAMESPACE=$(select_namespace) || return 1
    check_resource_count secrets "$NAMESPACE" || return 1
    print_separator

    if [[ "$NAMESPACE" == "all" ]]; then
        kubectl get secrets --all-namespaces
    else
        kubectl get secrets -n "$NAMESPACE"
    fi
}

describe_secret() {
    NAMESPACE=$(select_namespace) || return 1
    check_resource_count secrets "$NAMESPACE" || return 1

    local secret selected_ns prompt="Select Secret ❯ "

    if [[ "$NAMESPACE" == "all" ]]; then
        secret=$(kubectl get secrets --all-namespaces --no-headers | awk '{print $2 " (ns:" $1 ")"}' | fzf --prompt="$prompt")
        selected_ns=$(echo "$secret" | sed -E 's/.*\(ns:([^)]*)\).*/\1/')
        secret_name=$(echo "$secret" | awk '{print $1}')
        [[ -n "$secret_name" && -n "$selected_ns" ]] && kubectl describe secret "$secret_name" -n "$selected_ns"
    else
        secret=$(kubectl get secrets -n "$NAMESPACE" --no-headers | awk '{print $1}' | fzf --prompt="$prompt")
        [[ -n "$secret" ]] && kubectl describe secret "$secret" -n "$NAMESPACE"
    fi
}

show_cluster_info() {
    print_separator
    kubectl cluster-info
}

show_api_resources() {
    print_separator
    kubectl api-resources
}

list_nodes_info() {
    print_separator
    kubectl get nodes -o wide
}

list_namespaces() {
    print_separator
    kubectl get namespaces
}

describe_namespace() {
    local ns
    ns=$(kubectl get namespaces --no-headers | awk '{print $1}' | fzf --prompt="Select Namespace ❯ ")
    [[ -n "$ns" ]] && kubectl describe namespace "$ns"
}

list_namespace_labels() {
    print_separator
    kubectl get namespaces --show-labels
}

show_yaml_resource() {
    local resource_type
    resource_type=$(kubectl api-resources --verbs=list --namespaced -o name | sort | fzf --prompt="Select Resource Type ❯ ") || return

    frame_message "$CYAN" "Select Namespace"
    local NAMESPACE
    NAMESPACE=$({
        echo "all Namespaces"
        kubectl get ns --no-headers -o custom-columns=":metadata.name"
    } | fzf --prompt="Select Namespace ❯ ") || return
    frame_message_1 "${GREEN}" "[✓] Selected Namespace: $NAMESPACE"
    local resource_list
    if [[ "$NAMESPACE" == "all Namespaces" ]]; then
        resource_list=$(kubectl get "$resource_type" --all-namespaces --no-headers -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name")
    else
        resource_list=$(kubectl get "$resource_type" -n "$NAMESPACE" --no-headers -o custom-columns="NAME:.metadata.name")
    fi

    [[ -z "$resource_list" ]] && frame_message "$RED" "No $resource_type found." && return

    local selected_resource selected_ns selected_name
    if [[ "$NAMESPACE" == "all Namespaces" ]]; then
        selected_resource=$(echo "$resource_list" | fzf --prompt="Select Resource ❯ " | awk '{print $1, $2}')
        selected_ns=$(awk '{print $1}' <<<"$selected_resource")
        selected_name=$(awk '{print $2}' <<<"$selected_resource")
    else
        selected_name=$(echo "$resource_list" | fzf --prompt="Select Resource ❯ ")
        selected_ns="$NAMESPACE"
    fi

    [[ -z "$selected_name" ]] && frame_message "$RED" "No resource selected." && return

    local format
    format=$(choose_yaml_format) || return
    local tmp_yaml
    tmp_yaml=$(create_temp_file "_resource-yaml.yaml")

    if [[ "$format" == *Neat* ]]; then
        if spinner "Fetching Neat YAML for $resource_type/$selected_name" \
            "kubectl get $resource_type $selected_name -n $selected_ns -o yaml | kubectl neat > $tmp_yaml"; then
            open_yaml_output "$tmp_yaml" "$resource_type/$selected_name"
        else
            frame_message "$RED" "❌ Failed to fetch YAML."
        fi
    else
        if spinner "Fetching YAML for $resource_type/$selected_name" \
            "kubectl get $resource_type $selected_name -n $selected_ns -o yaml > $tmp_yaml"; then
            open_yaml_output "$tmp_yaml" "$resource_type/$selected_name"
        else
            frame_message "$RED" "❌ Failed to fetch YAML."
        fi
    fi
}

kube_show_api_resources() {
    local scope
    scope=$(printf "Namespaced only\nNon-namespaced only\nAll resources" | fzf --prompt="📘 Filter by scope ❯ ") || return

    local filter
    read -rp "🔍 Text filter (or Enter to skip): " filter

    local -a api_args=(api-resources)
    case "$scope" in
        "Namespaced only") api_args+=(--namespaced=true) ;;
        "Non-namespaced only") api_args+=(--namespaced=false) ;;
    esac

    if [[ -n "$filter" ]]; then
        kubectl "${api_args[@]}" | grep -i -- "$filter" | column -t
    else
        kubectl "${api_args[@]}" | column -t
    fi
}

get_pod_logs() {
    NAMESPACE=$(select_namespace) || return 1
    check_resource_count pods "$NAMESPACE" || return 1

    local pod selected_ns prompt="Select Pod for Logs ❯ "

    if [[ "$NAMESPACE" == "all" ]]; then
        pod=$(kubectl get pods --all-namespaces --no-headers | awk '{print $2 " (ns:" $1 ")"}' | fzf --prompt="$prompt")
        selected_ns=$(echo "$pod" | sed -E 's/.*\(ns:([^)]*)\).*/\1/')
        pod_name=$(echo "$pod" | awk '{print $1}')
        if [[ -n "$pod_name" && -n "$selected_ns" ]]; then
            check_pod_status_for_logs "$pod_name" "$selected_ns" || return 1
            kubectl logs "$pod_name" --all-containers=true -n "$selected_ns"
        fi
    else
        pod=$(kubectl get pods -n "$NAMESPACE" --no-headers | awk '{print $1}' | fzf --prompt="$prompt")
        if [[ -n "$pod" ]]; then
            check_pod_status_for_logs "$pod" "$NAMESPACE" || return 1
            kubectl logs "$pod" --all-containers=true -n "$NAMESPACE"
        fi
    fi
}

new_get_pods_docker_image_versions() {
    NAMESPACE="$1"
    POD_NAME="$2"

    if [[ -z $NAMESPACE ]]; then
        NAMESPACE=$(select_namespace) || return 1
    fi

    echo -e "${CYAN}Do you want to get the Docker image versions for:${RESET}"
    echo -e "${YELLOW}1.${RESET} ${GREEN}One specific pod${RESET}"
    echo -e "${YELLOW}2.${RESET} ${GREEN}All pods in namespace '${NAMESPACE}'${RESET}"
    echo -e "${CYAN}------------------------------------------${RESET}"
    read -r -p "$(echo -e "${CYAN}Enter your choice (1 or 2): ${RESET}")" choice

    if [[ "$choice" == "1" ]]; then
        POD_NAME=$(select_pod "$NAMESPACE") || return 1
        if [[ -z "$POD_NAME" ]]; then
            echo "Pod name is empty. Exiting..."
            return 1
        fi
        frame_message_1 "${GREEN}" "[✓] Selected Namespace: $NAMESPACE"
        frame_message_1 "${GREEN}" "[✓] Selected Pod: $POD_NAME"

        echo -e "\nComponent Versions for Pod '$POD_NAME':"
        kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].image}' 2>/dev/null \
            | awk '{
                printf "- %s:\n", $1;
                for(i=2; i<=NF; i++) {
                    printf "    - %s\n", $i;
                }
                printf "\n";  # Print an empty line
            }'

    elif [[ "$choice" == "2" ]]; then
        if [[ -z "$POD_NAME" ]]; then
            POD_NAME=$(ensure_pod_and_namespace "$NAMESPACE") || return 1
        fi
        echo -e "\nComponent Versions for All Pods in Namespace '$NAMESPACE':"
        kubectl get pods -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}' 2>/dev/null \
            | while read -r line; do
                echo "$line" | awk '{
                    printf "- %s:\n", $1;
                    for(i=2; i<=NF; i++) {
                        printf "    - %s\n", $i;
                    }
                    printf "\n";  # Print an empty line
                }'
            done

    else
        echo "Invalid choice. Exiting..."
        return 1
    fi
}

new_get_pods_replica_count() {
    NAMESPACE="$1"
    POD_NAME="$2"

    if [[ -z $NAMESPACE ]]; then
        NAMESPACE=$(select_namespace) || return 1
    fi

    echo -e "${CYAN}Do you want to get the replica count for:${RESET}"
    echo -e "${YELLOW}1.${RESET} ${GREEN}One specific pod${RESET}"
    echo -e "${YELLOW}2.${RESET} ${GREEN}All pods in namespace '${NAMESPACE}'${RESET}"
    echo -e "${CYAN}------------------------------------------${RESET}"
    read -r -p "$(echo -e "${CYAN}Enter your choice (1 or 2): ${RESET}")" choice

    if [[ "$choice" == "1" ]]; then
        POD_NAME=$(select_pod "$NAMESPACE") || return 1
        if [[ -z "$POD_NAME" ]]; then
            echo "Pod name is empty. Exiting..."
            return 1
        fi
        frame_message_1 "${GREEN}" "[✓] Selected Namespace: $NAMESPACE"
        frame_message_1 "${GREEN}" "[✓] Selected Pod: $POD_NAME"
        resource_type="$(kubectl describe pod "$POD_NAME" -n "$NAMESPACE" 2>/dev/null | grep "Controlled By" | awk '{$1=$2=""; print substr($0,3)}' | awk -F"/" '{print $1}')"
        resource_name="$(kubectl describe pod "$POD_NAME" -n "$NAMESPACE" 2>/dev/null | grep "Controlled By" | awk '{$1=$2=""; print substr($0,3)}' | awk -F"/" '{print $2}')"
        echo -e "\npod $POD_NAME Controlled by  $resource_type $resource_name"
        echo -e "\n${CYAN}pod $POD_NAME Controlled by  $resource_type $resource_name ${RESET}"
        replica_count=$(kubectl get "$resource_type" "$resource_name" -n "$NAMESPACE" -o jsonpath='{.status.replicas}' 2>/dev/null)
        if [[ -z "$replica_count" ]]; then
            echo -e "${RED}No replica count available for this pod ${POD_NAME} in namespace ${NAMESPACE}.${RESET}"
        else
            echo -e "\nReplica Count for Pod '$POD_NAME':" "$replica_count"
            echo -e "${CYAN}Replica Count for Pod '$POD_NAME': $replica_count ${RESET}"
        fi

    elif [[ "$choice" == "2" ]]; then
        echo -e "\nReplica Counts for All Pods in Namespace '$NAMESPACE':"
        kubectl get pods -n "$NAMESPACE" -o custom-columns="NAME:.metadata.name,REPLICAS:.status.replicas" --no-headers 2>/dev/null \
            | while read -r line; do
                POD_NAME=$(echo "$line" | awk '{print $1}')

                resource_type="$(kubectl describe pod "$POD_NAME" -n "$NAMESPACE" 2>/dev/null | grep "Controlled By" | awk '{$1=$2=""; print substr($0,3)}' | awk -F"/" '{print $1}')"
                resource_name="$(kubectl describe pod "$POD_NAME" -n "$NAMESPACE" 2>/dev/null | grep "Controlled By" | awk '{$1=$2=""; print substr($0,3)}' | awk -F"/" '{print $2}')"
                replica_count=$(kubectl get "$resource_type" "$resource_name" -n "$NAMESPACE" -o jsonpath='{.status.replicas}' 2>/dev/null)
                if [[ -z "$replica_count" ]]; then
                    replica_count="N/A"
                else
                    echo -e "\n${CYAN}pod $POD_NAME Controlled by  $resource_type $resource_name ${RESET}"
                    echo -e "${CYAN}Replica Count for Pod $POD_NAME : $replica_count ${RESET}"
                fi
            done

    else
        echo "Invalid choice. Exiting..."
        return 1
    fi
}

get_namespace_resources_list() {
    local namespace="$1"
    local resources0
    local resources
    local selected_resource
    local output

    if [[ -z $namespace ]]; then
        namespace=$(select_namespace) || return 1
    fi
    echo "Fetching all objects in namespace: $namespace"

    resources0="$(kubectl api-resources --namespaced=true -o name)"
    resources="all"$'\n'"$resources0"

    local colors=(31 32 33 34 35 36 37 90 91 92 93 94)

    selected_resource=$(echo "$resources" | fzf --prompt="Select a resource (or press Enter to select all): ")

    if [ -z "$selected_resource" ]; then
        selected_resource="all"
    fi

    if [ "$selected_resource" = "all" ]; then
        selected_resource=$(kubectl api-resources --namespaced=true -o name)
    fi

    for resource in $selected_resource; do
        output=$(kubectl get "$resource" -n "$namespace" --ignore-not-found)

        if [ -n "$output" ]; then
            local random_color=${colors[RANDOM % ${#colors[@]}]}
            echo -e "\e[${random_color}mResource: $resource\e[0m"
            echo -e "\e[${random_color}m$output\e[0m"
            echo
        fi
    done
}
