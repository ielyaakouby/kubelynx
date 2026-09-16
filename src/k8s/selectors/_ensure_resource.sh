#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
check_resource_count() {
    local resource_type="${1:-}"
    local namespace="${2:-}"

    local count

    if [[ "$namespace" == "all" ]]; then
        count=$(kubectl get "$resource_type" --all-namespaces --no-headers 2>/dev/null | wc -l)
    else
        count=$(kubectl -n "$namespace" get "$resource_type" --no-headers 2>/dev/null | wc -l)
    fi

    if [[ "$count" -eq 0 ]]; then
        frame_message "$RED" "❌ No ${resource_type} found in the namespace '${namespace}'. Returning to menu..."
        return 1
    else
        echo -e "${GREEN}[✓] $count ${resource_type}$([[ "$count" -gt 1 ]] && echo 's') found in the namespace '${namespace}'.${RESET}"
    fi
}

check_resource_count_() {
    local resource="$1"
    local ns="$2"
    local count
    count=$(kubectl get "$resource" -n "$ns" --no-headers 2>/dev/null | wc -l)
    [[ "$count" -eq 0 ]] && frame_message "$RED" "❌ No $resource found in namespace: $ns" && return 1
}

ensure_namespace_selected() {
    if [[ -z "$NAMESPACE" ]]; then
        NAMESPACE=$(select_namespace) || return 1
        frame_message_1 "${GREEN}" "[✓] Selected Namespace: $NAMESPACE"
    fi
}

ensure_node_selected() {
    NODE_NAME="${1:-}"

    local NODE_COUNT
    NODE_COUNT=$(kubectl get node --no-headers 2>/dev/null | wc -l)

    if [[ "$NODE_COUNT" -eq 0 ]]; then
        echo -e "${RED}❌ No nodes found in the cluster.${RESET}"
        return 1
    fi

    if [[ -z "$NODE_NAME" ]]; then
        NODE_NAME=$(select_node_name) || return 1
        frame_message "${GREEN}" "[✓] Selected Node: $NODE_NAME"
    fi
}

ensure_ingresse_and_namespace() {
    NAMESPACE="${1:-}"
    INGRESSE_NAME="${2:-}"

    ensure_namespace_selected || return 1

    check_resource_count "ingress" "$NAMESPACE" || return 1

    if [[ -z "$INGRESSE_NAME" ]]; then
        INGRESSE_NAME=$(select_ingress "$NAMESPACE") || return 1
        frame_message "${GREEN}" "[✓] Selected Ingress: $INGRESSE_NAME"
    fi
}

ensure_svc_and_namespace() {
    NAMESPACE="${1:-}"
    SVC_NAME="${2:-}"

    ensure_namespace_selected || return 1

    check_resource_count "svc" "$NAMESPACE" || return 1

    if [[ -z "$SVC_NAME" ]]; then
        SVC_NAME=$(select_svc "$NAMESPACE") || return 1
        frame_message "${GREEN}" "[✓] Selected Service: $SVC_NAME"
    fi
}

ensure_pod_and_namespace() {
    NAMESPACE="${1:-}"
    POD_NAME="${2:-}"

    ensure_namespace_selected || return 1

    check_resource_count "pod" "$NAMESPACE" || return 1

    if [[ -z "$POD_NAME" ]]; then
        POD_NAME=$(select_pod "$NAMESPACE") || return 1
        frame_message_1 "${GREEN}" "[✓] Selected Pod: $POD_NAME"
    fi
}

ensure_pod_and_namespace_ok() {
    NAMESPACE=""
    POD_NAME=""

    ensure_namespace_selected || return 1

    check_resource_count "pod" "$NAMESPACE" || return 1

    POD_NAME=$(select_pod "$NAMESPACE") || return 1
    frame_message_1 "${GREEN}" "[✓] Selected Pod: $POD_NAME"
}

ensure_deployment_and_namespace() {
    NAMESPACE="${1:-}"
    DEPLOYMENT_NAME="${2:-}"

    ensure_namespace_selected || return 1

    check_resource_count "deployment" "$NAMESPACE" || return 1

    if [[ -z "$DEPLOYMENT_NAME" ]]; then
        DEPLOYMENT_NAME=$(select_deployment "$NAMESPACE") || return 1
        frame_message "${GREEN}" "[✓] Selected Deployment: $DEPLOYMENT_NAME"
    fi
}

ensure_configmap_and_namespace() {
    NAMESPACE="${1:-}"
    CONFIGMAP_NAME="${2:-}"

    ensure_namespace_selected || return 1

    check_resource_count "configmap" "$NAMESPACE" || return 1

    if [[ -z "$CONFIGMAP_NAME" ]]; then
        CONFIGMAP_NAME=$(select_configmap "$NAMESPACE") || return 1
        frame_message "${GREEN}" "[✓] Selected ConfigMap: $CONFIGMAP_NAME"
    fi
}

ensure_statefulsets_and_namespace() {
    NAMESPACE="${1:-}"
    STATEFULSET_NAME="${2:-}"

    ensure_namespace_selected || return 1

    check_resource_count "statefulset" "$NAMESPACE" || return 1

    if [[ -z "$STATEFULSET_NAME" ]]; then
        STATEFULSET_NAME=$(select_statefulset "$NAMESPACE") || return 1
        frame_message "${GREEN}" "[✓] Selected StatefulSet: $STATEFULSET_NAME"
    fi
}

ensure_daemonset_and_namespace() {
    NAMESPACE="${1:-}"
    DAEMONSET_NAME="${2:-}"

    ensure_namespace_selected || return 1

    check_resource_count "daemonset" "$NAMESPACE" || return 1

    if [[ -z "$DAEMONSET_NAME" ]]; then
        DAEMONSET_NAME=$(select_daemonset "$NAMESPACE") || return 1
        frame_message "${GREEN}" "[✓] Selected DaemonSet: $DAEMONSET_NAME"
    fi
}

ensure_all_resources_and_namespace() {
    NAMESPACE=$(select_namespace) || return 1
    frame_message_1 "${GREEN}" "[✓] Selected Namespace: $NAMESPACE"

    RESOURCE_NAME=$(select_statefulset_daemonset_deployment "$NAMESPACE") || return 1
    if [[ -z "$RESOURCE_NAME" ]]; then
        echo -e "${RED}❌ Resource (StatefulSet/DaemonSet/Deployment) name is empty.${RESET}"
        return 1
    fi
    frame_message "${GREEN}" "[✓] Selected Resource: $RESOURCE_NAME"
}
