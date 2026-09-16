#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
kdelete_pod() {
    local pod_name="$1"
    local namespace="$2"

    if [ -z "$pod_name" ]; then
        read -p "Please enter the pod name you want to delete (or press Enter): " pod_name
        if [ -z "$pod_name" ]; then
            read -p "Please enter the namespace (or press Enter): " namespace
            if [ -z "$namespace" ]; then
                namespace=$(select_namespace) || exit 1
            fi
            selected_pod=$(select_pod "$namespace")
            pod_name="$selected_pod"
        fi
    fi

    if [[ -z $namespace ]]; then
        local pod_ns
        pod_ns=$(kubectl get pods --all-namespaces -o custom-columns=":metadata.namespace,:metadata.name" 2>/dev/null | grep "$pod_name" | awk '{print $1}')
    else
        pod_ns="$namespace"
    fi

    # Verify if the namespace was determined
    if [ -n "$pod_ns" ]; then
        echo "Deleting pod $pod_name in namespace $pod_ns..."
        kubectl -n "$pod_ns" delete pod "$pod_name"
    else
        echo "Namespace for pod $pod_name not found. No action taken."
    fi
}

kdelete_resource() {
    local resource_type="$1"
    local resource_name="$2"

    if [ -z "$resource_type" ]; then
        resource_type=$(select_resource_type) || exit 1
    fi

    if [ -z "$resource_name" ]; then
        selected_resource=$(select_resource "$resource_type")
        resource_name=$(echo "$selected_resource" | awk '{print $2}')
    fi

    if [[ -z $resource_name ]]; then
        echo "No resource name selected."
        exit 1
    fi

    local resource_ns
    resource_ns=$(echo "$selected_resource" | awk '{print $1}')

    if [ -n "$resource_ns" ]; then
        echo "Deleting $resource_type $resource_name in namespace $resource_ns..."
        kubectl -n "$resource_ns" delete "$resource_type" "$resource_name"
    else
        echo "Namespace for $resource_type $resource_name not found. No action taken."
    fi
}
# Dry-run mode
