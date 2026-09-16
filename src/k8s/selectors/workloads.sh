#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
ok_select_ingress() {
    local ns="${1:-all}"
    local ingresses_json
    local selected_ingress

    if [[ "$ns" == "all" ]]; then
        ingresses_json=$(kubectl get ingress --all-namespaces -o json 2>/dev/null)
    else
        ingresses_json=$(kubectl get ingress -n "$ns" -o json 2>/dev/null)
    fi

    if [[ -z "$ingresses_json" || "$ingresses_json" == "null" ]]; then
        frame_message "${RED}" "No ingress found in ${namespace} namespace(s)."
        return 1
    fi

    if [[ "$ns" == "all" ]]; then
        selected_ingress=$(echo "$ingresses_json" | jq -r '.items[] | "\(.spec.rules[0].host // "N/A")"' \
            | fzf --prompt "📦 Select an ingress host from any namespace: ")
    else
        selected_ingress=$(echo "$ingresses_json" | jq -r '.items[] | "\(.spec.rules[0].host // "N/A")"' \
            | fzf --prompt "📦 Select an ingress host in namespace $ns: ")
    fi

    if [[ -z "$selected_ingress" ]]; then
        frame_message "${RED}" "No ingress host selected."
        return 1
    fi

    echo "$selected_ingress"
}

select_node_name() {
    local nodes
    nodes=$(kubectl get nodes -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)
    selected_node=$(echo "$nodes" | fzf --prompt "📦 Select a node: ")
    if [[ -z "$selected_node" ]]; then
        frame_message "${RED}" "No node selected."
        return 1
    fi
    echo "$selected_node"
}

select_pod() {
    local ns="${1:-}"
    [[ -z "$ns" ]] && frame_message "$RED" "No namespace provided to select_pod_." && return 1

    local selected pod_name

    if [[ "$ns" == "all" ]]; then
        selected=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null \
            | awk '{print $2 " (ns:" $1 ")"}' \
            | fzf --prompt "📦 Select a pod (all namespaces): ")
        [[ -z "$selected" ]] && frame_message "$RED" "No pod selected." && return 1
        pod_name=$(echo "$selected" | awk '{print $1}')
    else
        pods=$(kubectl get pods -n "$ns" --no-headers -o custom-columns=":metadata.name" 2>/dev/null)
        selected=$(echo "$pods" | fzf --prompt "📦 Select a pod in namespace $ns: ")
        [[ -z "$selected" ]] && frame_message "$RED" "No pod selected." && return 1
        pod_name="$selected"
    fi

    echo "$pod_name"
}

is_pod_ns_exit() {
    local ns="${1:-}"
    local pod="$2"
    if [[ -z $ns ]]; then
        frame_message "${RED}" "No namespace selected."
        return 1
    fi
    if [[ -z "$pod" ]]; then
        frame_message "${RED}" "No pods found in namespace '$ns'."
        exit 0
    fi
}

select_configmap_name() {
    local ns="${1:-}"
    local configmap_name
    configmap_name=$(kubectl -n "$ns" get configmaps --no-headers -o custom-columns=":metadata.name" 2>/dev/null)
    selected_configmap_name=$(echo "$configmap_name" | fzf --prompt "📦 Select a configmap: ")
    if [[ -z "$selected_configmap_name" ]]; then
        frame_message "${RED}" "No configmap selected."
        return 1
    fi
    echo "$selected_configmap_name"
}

select_secret_name() {
    local ns="${1:-}"
    [[ -z "$ns" ]] && frame_message "${RED}" "No namespace provided." && return 1

    local selected secret_name

    if [[ "$ns" == "all" ]]; then
        selected=$(kubectl get secrets --all-namespaces --no-headers 2>/dev/null \
            | awk '{print $2 " (ns:" $1 ")"}' \
            | fzf --prompt "📦 Select a secret (all namespaces): ")
        [[ -z "$selected" ]] && frame_message "${RED}" "No secret selected." && return 1
        secret_name=$(echo "$selected" | awk '{print $1}')
    else
        secret_name=$(kubectl -n "$ns" get secrets --no-headers -o custom-columns=":metadata.name" 2>/dev/null)
        selected=$(echo "$secret_name" | fzf --prompt "📦 Select a secret in namespace $ns: ")
        [[ -z "$selected" ]] && frame_message "${RED}" "No secret selected." && return 1
        secret_name="$selected"
    fi

    echo "$secret_name"
}

select_deployment() {
    local ns="${1:-}"
    [[ -z "$ns" ]] && frame_message "${RED}" "No namespace provided." && return 1

    local selected deployment_name

    if [[ "$ns" == "all" ]]; then
        selected=$(kubectl get deployments --all-namespaces --no-headers 2>/dev/null \
            | awk '{print $2 " (ns:" $1 ")"}' \
            | fzf --prompt "📦 Select a deployment (all namespaces): ")
        [[ -z "$selected" ]] && frame_message "${RED}" "No deployment selected." && return 1
        deployment_name=$(echo "$selected" | awk '{print $1}')
    else
        local deployment
        deployment=$(kubectl get deployments -n "$ns" --no-headers -o custom-columns=":metadata.name" 2>/dev/null)
        selected=$(echo "$deployment" | fzf --prompt "📦 Select a deployment in namespace $ns: ")
        [[ -z "$selected" ]] && frame_message "${RED}" "No deployment selected." && return 1
        deployment_name="$selected"
    fi

    echo "$deployment_name"
}

select_statefulset() {
    local ns="${1:-}"
    [[ -z "$ns" ]] && frame_message "${RED}" "No namespace provided." && return 1

    local selected statefulset_name

    if [[ "$ns" == "all" ]]; then
        selected=$(kubectl get statefulsets.apps --all-namespaces --no-headers 2>/dev/null \
            | awk '{print $2 " (ns:" $1 ")"}' \
            | fzf --prompt "📦 Select a statefulset (all namespaces): ")
        [[ -z "$selected" ]] && frame_message "${RED}" "No statefulset selected." && return 1
        statefulset_name=$(echo "$selected" | awk '{print $1}')
    else
        local statefulsets
        statefulsets=$(kubectl get statefulsets.apps -n "$ns" --no-headers -o custom-columns=":metadata.name" 2>/dev/null)
        selected=$(echo "$statefulsets" | fzf --prompt "📦 Select a statefulset in namespace $ns: ")
        [[ -z "$selected" ]] && frame_message "${RED}" "No statefulset selected." && return 1
        statefulset_name="$selected"
    fi

    echo "$statefulset_name"
}

#### aghou

select_statefulset_daemonset_deployment() {
    local ns="${1:-}"
    [[ -z "$ns" ]] && frame_message "${RED}" "No namespace provided." && return 1

    local selected res_name

    if [[ "$ns" == "all" ]]; then
        selected=$(kubectl get statefulsets,deployments,daemonsets --all-namespaces --no-headers -o custom-columns="NAMESPACE:.metadata.namespace,KIND:.kind,NAME:.metadata.name" 2>/dev/null \
            | awk '{print $3 " [" $2 "] (ns:" $1 ")"}' \
            | fzf --prompt "📦 Select a resource (all namespaces): ")
        [[ -z "$selected" ]] && frame_message "${RED}" "No resource selected." && return 1
        res_name=$(echo "$selected" | awk '{print $1}')
    else
        selected=$(kubectl get statefulsets,deployments,daemonsets -n "$ns" --no-headers -o custom-columns="KIND:.kind,NAME:.metadata.name" 2>/dev/null \
            | awk '{print $2 " [" $1 "]"}' \
            | fzf --prompt "📦 Select a resource in namespace $ns: ")
        [[ -z "$selected" ]] && frame_message "${RED}" "No resource selected." && return 1
        res_name=$(echo "$selected" | awk '{print $1}')
    fi

    echo "$res_name"
}

select_daemonset() {
    local ns="${1:-}"
    [[ -z "$ns" ]] && frame_message "${RED}" "No namespace provided." && return 1

    local selected daemonset_name daemonset_ns

    if [[ "$ns" == "all" ]]; then
        selected=$(kubectl get daemonsets.apps --all-namespaces --no-headers 2>/dev/null \
            | awk '{print $2 " (ns:" $1 ")"}' \
            | fzf --prompt "📦 Select a daemonset (all namespaces): ")
        [[ -z "$selected" ]] && frame_message "${RED}" "No daemonset selected." && return 1
        daemonset_name=$(echo "$selected" | awk '{print $1}')
    else
        daemonset=$(kubectl get daemonsets.apps -n "$ns" --no-headers -o custom-columns=":metadata.name" 2>/dev/null)
        selected=$(echo "$daemonset" | fzf --prompt "📦 Select a daemonset in namespace $ns: ")
        [[ -z "$selected" ]] && frame_message "${RED}" "No daemonset selected." && return 1
        daemonset_name="$selected"
    fi

    echo "$daemonset_name"
}

select_svc() {
    local ns="${1:-}"
    [[ -z "$ns" ]] && frame_message "$RED" "No namespace provided to select_svc." && return 1

    local selected svc_name

    if [[ "$ns" == "all" ]]; then
        selected=$(kubectl get svc --all-namespaces --no-headers 2>/dev/null \
            | awk '{print $2 " (ns:" $1 ")"}' \
            | fzf --prompt "📦 Select a service (all namespaces): ")
        [[ -z "$selected" ]] && frame_message "$RED" "No service selected." && return 1
        svc_name=$(echo "$selected" | awk '{print $1}')
    else
        services=$(kubectl get svc -n "$ns" --no-headers -o custom-columns=":metadata.name" 2>/dev/null)
        selected=$(echo "$services" | fzf --prompt "📦 Select a service in namespace $ns: ")
        [[ -z "$selected" ]] && frame_message "$RED" "No service selected." && return 1
        svc_name="$selected"
    fi

    echo "$svc_name"
}

select_por_oldt() {
    local prompt="$1"
    local ports="$2"
    [[ -z "$ports" ]] && frame_message "$RED" "No ports found to select." && return 1
    echo "$ports" | tr ' ' '\n' | fzf --prompt "$prompt"
}

select_port() {
    local prompt="${1:-📦 Select a port: }"
    local ports="${2:-}"

    if [[ -z "$ports" ]]; then
        frame_message "$RED" "No ports found to select."
        return 1
    fi

    echo "$ports" | tr ' ' '\n' | fzf --prompt "$prompt"
}

ok_get_resources_kind_list() {
    kubectl api-resources --verbs=list --no-headers | awk '{print $1}' 2>/dev/null
}

get_resource_type() {
    resource_type=$(kubectl api-resources --no-headers 2>/dev/null | awk '{print $1}' | fzf --prompt="Select resource type: ")
    echo "$resource_type"
}

get_resource_name() {
    resource_type="$1"
    ns="$2"

    resource_name=$(kubectl -n "$ns" get "$resource_type" -o name 2>/dev/null | fzf --prompt="Select resource name: ")
    echo "$resource_name"
}

select_resource_name() {
    local ns="$1"
    [[ -z "$ns" ]] && frame_message "$RED" "No namespace provided." && return 1

    local selected res_name

    if [[ "$ns" == "all" ]]; then
        selected=$(kubectl get deploy,sts,ds --all-namespaces --no-headers -o custom-columns="NAMESPACE:.metadata.namespace,KIND:.kind,NAME:.metadata.name" 2>/dev/null \
            | awk '{print $3 " [" $2 "] (ns:" $1 ")"}' \
            | fzf --prompt="📦 Select resource (deployment/sts/ds, all namespaces) ❯ ") || return 1
        res_name=$(echo "$selected" | awk '{print $1}')
    else
        selected=$(kubectl get deploy,sts,ds -n "$ns" --no-headers -o custom-columns="KIND:.kind,NAME:.metadata.name" 2>/dev/null \
            | awk '{print $2 " [" $1 "]"}' \
            | fzf --prompt="📦 Select resource in namespace $ns ❯ ") || return 1
        res_name=$(echo "$selected" | awk '{print $1}')
    fi

    echo "$res_name"
}

# Added StatefulSet support
