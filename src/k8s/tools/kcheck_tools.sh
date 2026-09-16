#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
check_namespace_resources() {
    echo "CHECK: Starting check_namespace_resources function with arguments: $*"

    # Check if at least one namespace is provided
    if [[ $# -eq 0 ]]; then
        echo "Please provide at least one namespace as an argument."
        return 1
    fi

    for namespace in "$@"; do
        echo "CHECK: Processing namespace: $namespace"
        echo "Checking namespace: $namespace"

        # Check if the namespace exists
        if ! kubectl get namespace "$namespace" &>/dev/null; then
            echo "Namespace '$namespace' does not exist."
            echo "CHECK: Namespace '$namespace' does not exist. Skipping."
            continue
        fi

        echo "Namespace '$namespace' exists. Checking for resources..."

        # Check if there are any resources in the namespace
        echo "CHECK: Fetching resource types available for namespace '$namespace'."
        resources=$(kubectl api-resources --verbs=list --namespaced -o name \
            | xargs -I {} sh -c "kubectl get {} -n $namespace --no-headers 2>/dev/null" | wc -l)

        echo "CHECK: Number of resources found in namespace '$namespace': $resources"
        if [[ "$resources" -eq 0 ]]; then
            echo "Namespace '$namespace' exists but has no resources."
            echo "CHECK: No resources found in namespace '$namespace'."
        else
            echo "Namespace '$namespace' exists and contains $resources resource(s)."
            echo "CHECK: Resources found in namespace '$namespace': $resources"
        fi
    done

    echo "CHECK: Completed check_namespace_resources function."
}

kcheck_buffers_usage_ok() {
    local pattern="$1"
    if [[ -z "$pattern" ]]; then
        echo "Usage: check_buffers_usage <pattern>"
        return 1
    fi
    kubectl get pods --all-namespaces --no-headers | grep "$pattern" | awk '{print $1, $2}' | while read namespace pod; do
        local usage=$(kubectl exec -n "$namespace" "$pod" -- du -ksh buffers 2>/dev/null)

        if [[ $? -eq 0 ]]; then
            local size=$(echo "$usage" | awk '{print $1}') # Get the size in kilobytes
            echo "buffers for pod: $namespace/$pod : $size"
            results+=("$namespace/$pod : $size K") # Store the result in the array
        else
            echo "$namespace/$pod : Error retrieving usage" # Store error in results
        fi
    done
}

# kcheck_buffers_usage "fluentbit-m"

kcheck_buffers_usage() {
    local pattern="$1"
    local namespace="${2:-all}"
    local no_pods_msg="${YELLOW}No pods found matching pattern '$pattern' in namespace '$namespace'.${RESET}"
    local usage_msg="${GREEN}Usage:${RESET} kcheck_buffers_usage <pattern> [namespace|all]"

    if [[ -z "$pattern" ]]; then
        echo -e "$usage_msg"
        return 1
    fi

    local pods
    if [[ "$namespace" == "all" ]]; then
        pods=$(kubectl get pods --all-namespaces --no-headers | grep "$pattern")
        #namespace="all namespaces"
    else
        pods=$(kubectl get pods -n "$namespace" --no-headers | grep "$pattern" | awk -v ns="$namespace" '{print ns, $0}')
    fi

    if [[ -z "$pods" ]]; then
        echo -e "$no_pods_msg"
        return 1
    fi

    echo -e "\n${CYAN}Namespace:${RESET} $namespace"
    echo "$pods" | awk '{print $1, $2}' | while read pod_namespace pod_name; do
        local usage=$(kubectl exec -n "$pod_namespace" "$pod_name" -- du -ksh buffers 2>/dev/null)

        if [[ $? -eq 0 ]]; then
            local size=$(echo "$usage" | awk '{print $1}')
            echo -e "  ${BLUE}Buffer usage for pod${RESET} ${CYAN}$pod_namespace/$pod_name${RESET}: ${GREEN}$size${RESET}"
        else
            echo -e "  ${RED}Error:${RESET} Unable to retrieve usage for ${CYAN}$pod_namespace/$pod_name${RESET}"
        fi
    done | sort -h
}
