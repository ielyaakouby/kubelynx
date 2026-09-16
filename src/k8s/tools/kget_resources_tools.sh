#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
# Display pods by status

display_pods() {
    local namespace_option="$1"
    local status="$2"
    local pods_output

    case "$status" in
        Not_Running) pods_output=$(kubectl get pods "$namespace_option" --no-headers 2>/dev/null | grep -vE "Running|Completed") ;;
        All) pods_output=$(kubectl get pods "$namespace_option" --no-headers 2>/dev/null) ;;
        *) pods_output=$(kubectl get pods "$namespace_option" --no-headers 2>/dev/null | grep "$status") ;;
    esac

    [[ -n "$pods_output" ]] && echo -e "${CYAN}\nPods with ${status} status:${RESET}\n"

    if [[ "$namespace_option" == "--all-namespaces" ]]; then
        # On trie par namespace
        echo "$pods_output" | sed '/^$/d' | awk '{print $1}' | sort -u | while read -r ns; do
            echo -e "${YELLOW} ### namespace : $ns ### ${RESET}"
            echo "$pods_output" | grep "^$ns " | while read -r line; do
                if echo "$line" | grep -qE "CrashLoopBackOff|ImagePullBackOff|Error|Failed"; then
                    echo -e "${RED}  $line${RESET}"
                elif echo "$line" | grep -qE "Terminating|Unknown|Waiting|Completed"; then
                    echo -e "${ORANGE}  $line${RESET}"
                else
                    echo -e "${CYAN}  $line${RESET}"
                fi
            done
            echo
        done
    else
        echo "$pods_output" | sed '/^$/d' | while read -r line; do
            if echo "$line" | grep -qE "CrashLoopBackOff|ImagePullBackOff|Error|Failed"; then
                echo -e "${RED}  $line${RESET}"
            elif echo "$line" | grep -qE "Terminating|Unknown|Waiting|Completed"; then
                echo -e "${ORANGE}  $line${RESET}"
            else
                echo -e "${CYAN}  $line${RESET}"
            fi
        done
    fi
}

# Get detailed Pod status

kget_pod_status() {
    local namespace="$1" pod_name="$2"

    if [[ -z "$namespace" || -z "$pod_name" ]]; then
        namespace=$(select_namespace) || return 1
        pod_name=$(select_pod "$namespace") || return 1
        [[ -z "$namespace" || -z "$pod_name" ]] && echo "Namespace and/or Pod name is empty. Exiting..." && return 1
        frame_message "${GREEN}" "Selected Namespace: $namespace"
        frame_message "${GREEN}" "Selected Pod: $pod_name"
    fi

    local pod_json
    pod_json=$(kubectl -n "$namespace" get pod "$pod_name" -o json 2>/dev/null) || return 1

    local pod_status container_names container_statuses
    pod_status=$(echo "$pod_json" | jq -r '.status.conditions[] | select(.type=="Ready") | .status')
    echo

    [[ "$pod_status" == "True" ]] && echo -e "${COLOR_GREEN}✦ Pod Status: READY${COLOR_RESET}" || echo -e "${COLOR_RED}✦ Pod Status: NOT READY${COLOR_RESET}"

    echo -e "${COLOR_CYAN}✦ Containers:${COLOR_RESET}"
    container_names=$(echo "$pod_json" | jq -r '.status.containerStatuses[].name')
    container_statuses=$(echo "$pod_json" | jq -c '.status.containerStatuses[]')

    while read -r container; do
        local container_name container_ready container_started container_restart_count container_started_at container_unready_reason
        container_name=$(echo "$container" | jq -r '.name')
        container_ready=$(echo "$container" | jq -r '.ready')
        container_started=$(echo "$container" | jq -r '.started')
        container_restart_count=$(echo "$container" | jq -r '.restartCount')
        container_started_at=$(echo "$container" | jq -r '.state.running.startedAt // empty')
        container_unready_reason=$(echo "$container" | jq -r '.state.terminated.reason // empty')

        echo -e "  - ${COLOR_CYAN}${container_name}${COLOR_RESET}"
        echo -e "    Ready:     $([[ "$container_ready" == "true" ]] && echo "${COLOR_GREEN}Yes${COLOR_RESET}" || echo "${COLOR_RED}No${COLOR_RESET}")"
        echo -e "    Started:   $([[ "$container_started" == "true" ]] && echo "${COLOR_GREEN}Yes${COLOR_RESET} (${container_started_at})" || echo "${COLOR_RED}No${COLOR_RESET}")"
        echo -e "    Restarts:  ${container_restart_count}"
        [[ -n "$container_unready_reason" ]] && echo -e "    Reason:    ${COLOR_YELLOW}${container_unready_reason}${COLOR_RESET}"
    done <<<"$container_statuses"

    echo
}

# Get pods list sorted by age

get_pods_list_sort_by_age() {
    local namespace
    namespace=$(select_namespace) || return 1
    echo -e "${GREEN}[✓] Selected Namespace: ${YELLOW}$namespace${RESET}\n"
    kubectl get pods -n "$namespace" --sort-by='.metadata.creationTimestamp' 2>/dev/null
}

# General pods listing and filtering

select_pod_status() {
    local statuses=("All" "Running" "Pending" "Succeeded" "Failed" "Unknown" "CrashLoopBackOff" "ImagePullBackOff" "Completed" "Waiting" "Error" "Not_Running")
    printf "%s\n" "${statuses[@]}" | fzf --header="Select Pod Status"
}

get_pods_list_by_status() {
    local choice namespace_option pod_status
    echo -e "${CYAN}\nSelect an option:${RESET}"
    echo -e "${GREEN} 1) Namespace${RESET}"
    echo -e "${GREEN} 2) All namespaces${RESET}\n"
    read -rp "Enter choice (1/2): " choice

    case "$choice" in
        1)
            namespace=$(select_namespace) || return 1
            namespace_option="--namespace=$namespace"
            ;;
        2)
            namespace_option="--all-namespaces"
            ;;
        *)
            echo -e "${RED}Invalid choice.${RESET}" && return
            ;;
    esac

    pod_status=$(select_pod_status) || return
    [[ -z "$pod_status" ]] && echo -e "${RED}No status selected.${RESET}" && return

    if [[ "$pod_status" == "All" ]]; then
        kubectl get pods "$namespace_option" 2>/dev/null
    else
        display_pods "$namespace_option" "$pod_status"
    fi

    echo
}

# Filtered resources

kget_filtered_resources() {
    local resource_type="$1"
    local filter="$2"

    if [[ -z "$resource_type" ]]; then
        resource_type=$(select_resource_type)
        [[ -z "$resource_type" ]] && echo "No resource type selected." && return 1
    fi

    if [[ -z "$filter" ]]; then
        read -rp "Enter the filter to search for: " filter
        [[ -z "$filter" ]] && echo "No filter provided." && return 1
    fi

    local result namespaces_list
    result=$(kubectl get "$resource_type" --all-namespaces 2>/dev/null | grep "$filter")
    namespaces_list=$(echo "$result" | awk '{print $1}' | sort -u)

    for ns in $namespaces_list; do
        echo -e "└─┬ namespace: $ns ─────────────────────────────────────"
        echo "  │"
        kubectl -n "$ns" get "$resource_type" --no-headers 2>/dev/null | grep "$filter" | while read -r line; do
            echo -e "  │ ${CYAN}$line${RESET}"
        done
        echo -e "  └──────────────────────────────────────────────────────"
    done
}

# Resource filtering by Label/Annotation/EmptyDir

kget_resources_filter_by_label_name() {
    kubectl get "$1" -A -o json 2>/dev/null | jq -r --arg name "$2" '.items[] | select(.metadata.labels[$name]) | "\(.metadata.namespace)/\(.metadata.name) → Label: \(.metadata.labels[$name])"'
}

kget_resources_filter_by_annotation_name() {
    kubectl get "$1" -A -o json 2>/dev/null | jq -r --arg name "$2" '.items[] | select(.metadata.annotations[$name]) | "\(.metadata.namespace)/\(.metadata.name) → Annotation: \(.metadata.annotations[$name])"'
}

kget_pods_list_with_emptydir() {
    kubectl get pods -A -o json 2>/dev/null | jq -r '.items[] | select(.spec.volumes[]? | has("emptyDir")) | "\(.metadata.namespace)/\(.metadata.name) → emptyDir Volume"'
}

kget_resources_filter_by() {
    local action resource filter

    action=$(printf "Filter by Label\nFilter by Annotation\nList Pods with emptyDir" | fzf --prompt="Select an action: ")
    [[ -z "$action" ]] && echo "No action selected." && exit 1

    if [[ "$action" == "List Pods with emptyDir" ]]; then
        kget_pods_list_with_emptydir
        exit 0
    fi

    resource=$(printf "pods\nservices\ndeployments\nstatefulsets\ndaemonsets\npersistentvolumes\npersistentvolumeclaims\nsecrets\nconfigmaps" | fzf --prompt="Select resource type:: ")
    [[ -z "$resource" ]] && echo "No resource selected." && exit 1

    read -rp "Enter the ${action#Filter by } name: " filter
    [[ -z "$filter" ]] && echo "No filter name provided." && exit 1

    if [[ "$action" == "Filter by Label" ]]; then
        kget_resources_filter_by_label_name "$resource" "$filter"
    else
        kget_resources_filter_by_annotation_name "$resource" "$filter"
    fi
}

# Count Kubernetes Resources

kget_resource_total() {
    local choice namespace_option
    choice=$(printf "Specific namespace\nAll namespaces" | fzf --prompt="Select counting scope: ")

    case "$choice" in
        Specific*)
            namespace=$(select_namespace) || return 1
            namespace_option="--namespace=$namespace"
            ;;
        All*)
            namespace_option="--all-namespaces"
            ;;
        *) echo "Invalid choice." && return ;;
    esac

    declare -A resources=(
        [DaemonSets]=daemonsets
        [Deployments]=deployments
        [StatefulSets]=statefulsets
        [Pods]=pods
        [Secrets]=secrets
        [ConfigMaps]=configmaps
        [Services]=services
        [Ingresses]=ingresses
        [PVC]=pvc
        [PV]=pv
        [CronJobs]=cronjobs
        [Jobs]=jobs
        [CRDs]=crds
        [StorageClasses]=storageclass
    )

    echo -e "${YELLOW}Resource Counts:${RESET}"
    local total=0
    for name in "${!resources[@]}"; do
        local count
        count=$(kubectl get "${resources[$name]}" $namespace_option --no-headers 2>/dev/null | wc -l)
        printf "%-25s %d\n" "$name" "$count"
        total=$((total + count))
    done
    echo -e "${MAGENTA}--------------------------------------${RESET}"
    printf "%-25s %d\n" "Total" "$total"
}

# End

# Wide output support
