#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
select_node_kget_node_infos() {
    local nodes
    nodes=$(kubectl get nodes --no-headers -o custom-columns=":metadata.name" 2>/dev/null)
    selected_node=$(echo -e "$nodes" | fzf --prompt "Select a node: ")
    if [[ -z "$selected_node" ]]; then
        frame_message "${RED}" "No node selected. Exiting."
        exit 1
    fi
    echo -e "$selected_node"
}

kget_node_info() {
    local node_name=$1

    TMP_NODE_JSON_FILE=$(mktemp)
    TMP_DESC_FILE=$(mktemp)
    TMP_PODS_FILE=$(mktemp)

    if [[ -z "$node_name" ]]; then
        node_name=$(select_node_kget_node_infos) || exit 1
    fi

    check_snipp "Fetching node '$node_name' info" \
        "kubectl get node \"$node_name\" -o json > \"$TMP_NODE_JSON_FILE\""

    node_json=$(<"$TMP_NODE_JSON_FILE")

    if [[ -z "$node_json" ]]; then
        frame_message "${RED}" "[!] Node not found."
        return 1
    fi

    check_snipp "Describing node '$node_name'" \
        "kubectl describe node \"$node_name\" > \"$TMP_DESC_FILE\""

    check_snipp "Fetching pods on node '$node_name'" \
        "kubectl get pods --all-namespaces --field-selector spec.nodeName=\"$node_name\" -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name} {.status.phase} {.status.containerStatuses[*].ready}{\"\\n\"}{end}' > \"$TMP_PODS_FILE\""

    PODS_DATA=$(<"$TMP_PODS_FILE")

    # Section selection with fzf
    local available_sections=(
        "Name"
        "Status"
        "CPU"
        "Memory"
        "Pod Capacity"
        "Architecture"
        "Kernel Version"
        "OS"
        "Container Runtime"
        "Labels"
        "Annotations"
        "Conditions"
        "Pods"
        "Done message"
    )

    local selected_sections
    selected_sections=$(printf "%s\n" "${available_sections[@]}" \
        | fzf --multi --prompt="Select node info to display: " --header="Press TAB to select multiple, or ENTER for all")

    if [[ -z "$selected_sections" ]]; then
        selected_sections="all"
    fi

    show_section() {
        local key="$1"
        [[ "$selected_sections" == "all" || "$selected_sections" == *"$key"* ]]
    }

    # Extract node details
    NAME=$(jq -r '.metadata.name' <<<"$node_json")
    STATUS=$(kubectl get node "$node_name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    STATUS_ICON=$([[ "$STATUS" == "True" ]] && echo "Ready" || echo "Not Ready")
    CPU_ALLOCATABLE=$(jq -r '.status.allocatable.cpu' <<<"$node_json")
    MEMORY_ALLOCATABLE=$(jq -r '.status.allocatable.memory' <<<"$node_json")

    MEMORY_VALUE=$(sed -E 's/([0-9]+)([a-zA-Z]+)/\1/' <<<"$MEMORY_ALLOCATABLE")
    MEMORY_UNIT=$(sed -E 's/[0-9]+([a-zA-Z]+)/\1/' <<<"$MEMORY_ALLOCATABLE")
    if [[ "$MEMORY_UNIT" == "Gi" ]]; then
        MEMORY_ALLOCATABLE_ok=$((MEMORY_VALUE))
    elif [[ "$MEMORY_UNIT" == "Mi" ]]; then
        MEMORY_ALLOCATABLE_ok=$((MEMORY_VALUE / 1024))
    elif [[ "$MEMORY_UNIT" == "Ki" ]]; then
        MEMORY_ALLOCATABLE_ok=$((MEMORY_VALUE / 1024 / 1024))
    else
        MEMORY_ALLOCATABLE_ok="$MEMORY_ALLOCATABLE"
    fi

    POD_CAPACITY=$(jq -r '.status.capacity.pods' <<<"$node_json")
    ARCHITECTURE=$(jq -r '.status.nodeInfo.architecture' <<<"$node_json")
    KERNEL_VERSION=$(jq -r '.status.nodeInfo.kernelVersion' <<<"$node_json")
    OS=$(jq -r '.status.nodeInfo.operatingSystem' <<<"$node_json")
    OS_IMAGE=$(jq -r '.status.nodeInfo.osImage' <<<"$node_json")
    CONTAINER_RUNTIME=$(jq -r '.status.nodeInfo.containerRuntimeVersion' <<<"$node_json")
    LABELS=$(jq -r '.metadata.labels | to_entries[] | "- \(.key): \(.value)"' <<<"$node_json")
    ANNOTATIONS=$(jq -r '.metadata.annotations | to_entries[] | "- \(.key): \(.value)"' <<<"$node_json")
    CONDITIONS=$(<"$TMP_DESC_FILE")

    TOTAL_PODS=$(echo "$PODS_DATA" | wc -l)
    PODS_FAILED=$(echo "$PODS_DATA" | awk '($3 != "Running" && $3 != "Succeeded" && $3 != "Completed") && $4 == "false"')
    TOTAL_PODS_FAILED=$(echo "$PODS_FAILED" | wc -l)
    TOTAL_PODS_RUNNING=$((TOTAL_PODS - TOTAL_PODS_FAILED))

    # Display selected sections
    show_section "Name" && echo -e "\nName: $NAME"
    show_section "Status" && echo -e "Status: $STATUS_ICON"
    show_section "CPU" && echo -e "CPU: $CPU_ALLOCATABLE"
    show_section "Memory" && echo -e "Memory: ${MEMORY_ALLOCATABLE_ok} Gi"
    show_section "Pod Capacity" && echo -e "Pod Capacity: $POD_CAPACITY"
    show_section "Architecture" && echo -e "Architecture: $ARCHITECTURE"
    show_section "Kernel Version" && echo -e "Kernel: $KERNEL_VERSION"
    show_section "OS" && echo -e "OS: $OS ($OS_IMAGE)"
    show_section "Container Runtime" && echo -e "Runtime: $CONTAINER_RUNTIME"

    if show_section "Labels"; then
        echo -e "\nLabels:"
        [[ -z "$LABELS" ]] && echo "  > None" || echo "$LABELS" | while read -r l; do echo "  $l"; done
    fi

    if show_section "Annotations"; then
        echo -e "\nAnnotations:"
        [[ -z "$ANNOTATIONS" ]] && echo "  > None" || echo "$ANNOTATIONS" | while read -r a; do echo "  $a"; done
    fi

    show_section "Conditions" && echo -e "\nConditions:\n$CONDITIONS"

    if show_section "Pods"; then
        echo -e "\nPods on Node ($TOTAL_PODS):"
        if [[ "$TOTAL_PODS_FAILED" -eq 0 ]]; then
            echo "  > $TOTAL_PODS_RUNNING running, no failed pods."
        else
            echo "  > $TOTAL_PODS_FAILED pods have issues:"
            echo "$PODS_FAILED"
        fi
    fi

    show_section "Done message" && echo -e "\n[✓] Node information retrieval completed."

    rm -f "$TMP_NODE_JSON_FILE" "$TMP_DESC_FILE" "$TMP_PODS_FILE"
}

kget_pod_info() {
    local namespace="$1"
    local pod_name="$2"

    if [[ -z "$namespace" || -z "$pod_name" ]]; then
        namespace=$(select_namespace) || return 1
        pod_name=$(select_pod "$namespace") || return 1
    fi

    TMP_POD_JSON_FILE=$(mktemp)
    TMP_LOG_FILE=$(mktemp)

    check_snipp "Fetching pod '$pod_name' info from namespace '$namespace'" \
        "kubectl get pod \"$pod_name\" -n \"$namespace\" -o json > \"$TMP_POD_JSON_FILE\""

    pod_json=$(<"$TMP_POD_JSON_FILE")

    if [[ -z "$pod_json" ]]; then
        echo -e "[!] Pod not found in namespace $namespace"
        return 1
    fi

    NAME=$(jq -r '.metadata.name' <<<"$pod_json")
    NODE_NAME=$(jq -r '.spec.nodeName // "N/A"' <<<"$pod_json")
    READY=$(jq -r '.status.containerStatuses | length as $total | map(select(.ready)) | length as $ready | "\($ready)/\($total)"' <<<"$pod_json")
    STATUS=$(jq -r '.status.phase' <<<"$pod_json")
    RESTARTS=$(jq -r '.status.containerStatuses | map(.restartCount) | add' <<<"$pod_json")
    CONTAINERS=$(jq -r '.spec.containers[].name' <<<"$pod_json" | paste -sd, -)
    IMAGE=$(jq -r '.spec.containers[] | "\(.name): \(.image)"' <<<"$pod_json")
    KIND=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null)
    LABELS=$(jq -r '.metadata.labels | to_entries[] | "- \(.key): \(.value)"' <<<"$pod_json")
    ANNOTATIONS=$(jq -r '.metadata.annotations | to_entries[] | "- \(.key): \(.value)"' <<<"$pod_json")

    local available_sections=(
        "Name"
        "Namespace"
        "Node Name"
        "Status"
        "Restarts"
        "Containers"
        "Images"
        "Kind"
        "Labels"
        "Annotations"
    )

    local selected_sections
    selected_sections=$(printf "%s
" "${available_sections[@]}" \
        | fzf --multi --prompt="Select pod info to display: " --header="TAB to select multiple, ENTER for all")

    if [[ -z "$selected_sections" ]]; then
        selected_sections="all"
    fi

    show_section() {
        local key="$1"
        [[ "$selected_sections" == "all" || "$selected_sections" == *"$key"* ]]
    }

    echo ""
    show_section "Name" && echo "Name: $NAME"
    show_section "Namespace" && echo "Namespace: $namespace"
    show_section "Node Name" && echo "Node Name: $NODE_NAME"
    show_section "Status" && echo "Status: $STATUS ($READY ready)"
    show_section "Restarts" && echo "Restart Count: $RESTARTS"
    show_section "Containers" && echo "Containers: $CONTAINERS"
    show_section "Images" && echo "$IMAGE"
    show_section "Kind" && echo "Kind: $KIND"

    if show_section "Labels"; then
        echo -e "
Labels:"
        [[ -z "$LABELS" ]] && echo "  > None" || echo "$LABELS"
    fi

    if show_section "Annotations"; then
        echo -e "
Annotations:"
        [[ -z "$ANNOTATIONS" ]] && echo "  > None" || echo "$ANNOTATIONS"
    fi

    echo -e "
[✓] Pod information retrieval completed."

    rm -f "$TMP_POD_JSON_FILE" "$TMP_LOG_FILE"
}

kget_deployment_info() {
    local namespace="$1"
    local deploy_name="$2"

    if [[ -z "$namespace" || -z "$deploy_name" ]]; then
        namespace=$(select_namespace) || return 1
        deploy_name=$(kubectl get deploy -n "$namespace" --no-headers -o custom-columns=":.metadata.name" | fzf --prompt="Select deployment: ") || return 1
    fi

    TMP_DEPLOY_JSON_FILE=$(mktemp)

    check_snipp "Fetching deployment '$deploy_name' in namespace '$namespace'" \
        "kubectl get deploy \"$deploy_name\" -n \"$namespace\" -o json > \"$TMP_DEPLOY_JSON_FILE\""

    deploy_json=$(<"$TMP_DEPLOY_JSON_FILE")

    if [[ -z "$deploy_json" ]]; then
        echo -e "[!] Deployment not found in namespace $namespace"
        return 1
    fi

    NAME=$(jq -r '.metadata.name' <<<"$deploy_json")
    REPLICAS=$(jq -r '.spec.replicas' <<<"$deploy_json")
    AVAILABLE=$(jq -r '.status.availableReplicas // 0' <<<"$deploy_json")
    UPDATED=$(jq -r '.status.updatedReplicas // 0' <<<"$deploy_json")
    IMAGE=$(jq -r '.spec.template.spec.containers[] | "\(.name): \(.image)"' <<<"$deploy_json")
    LABELS=$(jq -r '.metadata.labels | to_entries[] | "- \(.key): \(.value)"' <<<"$deploy_json")
    ANNOTATIONS=$(jq -r '.metadata.annotations | to_entries[] | "- \(.key): \(.value)"' <<<"$deploy_json")
    SELECTOR=$(jq -r '.spec.selector.matchLabels | to_entries[] | "- \(.key): \(.value)"' <<<"$deploy_json")

    local available_sections=(
        "Name"
        "Namespace"
        "Replicas"
        "Image"
        "Labels"
        "Annotations"
        "Selector"
    )

    local selected_sections
    selected_sections=$(printf "%s\n" "${available_sections[@]}" \
        | fzf --multi --prompt="Select deployment info to display: " --header="TAB to select multiple, ENTER for all")

    if [[ -z "$selected_sections" ]]; then
        selected_sections="all"
    fi

    show_section() {
        local key="$1"
        [[ "$selected_sections" == "all" || "$selected_sections" == *"$key"* ]]
    }

    echo ""
    show_section "Name" && echo "Name: $NAME"
    show_section "Namespace" && echo "Namespace: $namespace"
    show_section "Replicas" && echo "Replicas: $AVAILABLE available / $UPDATED updated / desired $REPLICAS"
    show_section "Image" && printf 'Image(s):\n%s\n' "$IMAGE"

    if show_section "Labels"; then
        echo -e "\nLabels:"
        [[ -z "$LABELS" ]] && echo "  > None" || echo "$LABELS"
    fi

    if show_section "Annotations"; then
        echo -e "\nAnnotations:"
        [[ -z "$ANNOTATIONS" ]] && echo "  > None" || echo "$ANNOTATIONS"
    fi

    if show_section "Selector"; then
        echo -e "\nSelector:"
        [[ -z "$SELECTOR" ]] && echo "  > None" || echo "$SELECTOR"
    fi

    echo -e "\n[✓] Deployment information retrieval completed."

    rm -f "$TMP_DEPLOY_JSON_FILE"
}

kget_statefulset_info() {
    local namespace="$1"
    local sts_name="$2"

    if [[ -z "$namespace" || -z "$sts_name" ]]; then
        namespace=$(select_namespace) || return 1
        sts_name=$(kubectl get statefulset -n "$namespace" --no-headers -o custom-columns=":.metadata.name" | fzf --prompt="Select statefulset: ") || return 1
    fi

    TMP_STS_JSON_FILE=$(mktemp)

    check_snipp "Fetching statefulset '$sts_name' in namespace '$namespace'" \
        "kubectl get statefulset \"$sts_name\" -n \"$namespace\" -o json > \"$TMP_STS_JSON_FILE\""

    sts_json=$(<"$TMP_STS_JSON_FILE")

    if [[ -z "$sts_json" ]]; then
        echo -e "[!] StatefulSet not found in namespace $namespace"
        return 1
    fi

    NAME=$(jq -r '.metadata.name' <<<"$sts_json")
    REPLICAS=$(jq -r '.spec.replicas' <<<"$sts_json")
    READY=$(jq -r '.status.readyReplicas // 0' <<<"$sts_json")
    CURRENT=$(jq -r '.status.currentReplicas // 0' <<<"$sts_json")
    IMAGE=$(jq -r '.spec.template.spec.containers[] | "\(.name): \(.image)"' <<<"$sts_json")
    LABELS=$(jq -r '.metadata.labels | to_entries[] | "- \(.key): \(.value)"' <<<"$sts_json")
    ANNOTATIONS=$(jq -r '.metadata.annotations | to_entries[] | "- \(.key): \(.value)"' <<<"$sts_json")
    SELECTOR=$(jq -r '.spec.selector.matchLabels | to_entries[] | "- \(.key): \(.value)"' <<<"$sts_json")

    local available_sections=(
        "Name"
        "Namespace"
        "Replicas"
        "Image"
        "Labels"
        "Annotations"
        "Selector"
    )

    local selected_sections
    selected_sections=$(printf "%s
" "${available_sections[@]}" \
        | fzf --multi --prompt="Select statefulset info to display: " --header="TAB to select multiple, ENTER for all")

    if [[ -z "$selected_sections" ]]; then
        selected_sections="all"
    fi

    show_section() {
        local key="$1"
        [[ "$selected_sections" == "all" || "$selected_sections" == *"$key"* ]]
    }

    echo ""
    show_section "Name" && echo "Name: $NAME"
    show_section "Namespace" && echo "Namespace: $namespace"
    show_section "Replicas" && echo "Replicas: $READY ready / $CURRENT current / desired $REPLICAS"
    show_section "Image" && echo -e "Image(s):
$IMAGE"

    if show_section "Labels"; then
        echo -e "
Labels:"
        [[ -z "$LABELS" ]] && echo "  > None" || echo "$LABELS"
    fi

    if show_section "Annotations"; then
        echo -e "
Annotations:"
        [[ -z "$ANNOTATIONS" ]] && echo "  > None" || echo "$ANNOTATIONS"
    fi

    if show_section "Selector"; then
        echo -e "
Selector:"
        [[ -z "$SELECTOR" ]] && echo "  > None" || echo "$SELECTOR"
    fi

    echo -e "
[✓] StatefulSet information retrieval completed."

    rm -f "$TMP_STS_JSON_FILE"
}

kget_secret_info() {
    local namespace="$1"
    local secret_name="$2"

    if [[ -z "$namespace" || -z "$secret_name" ]]; then
        namespace=$(select_namespace) || return 1
        secret_name=$(kubectl get secret -n "$namespace" --no-headers -o custom-columns=":.metadata.name" | fzf --prompt="Select secret: ") || return 1
    fi

    TMP_SECRET_JSON_FILE=$(mktemp)

    check_snipp "Fetching secret '$secret_name' in namespace '$namespace'" \
        "kubectl get secret \"$secret_name\" -n \"$namespace\" -o json > \"$TMP_SECRET_JSON_FILE\""

    secret_json=$(<"$TMP_SECRET_JSON_FILE")

    if [[ -z "$secret_json" ]]; then
        echo -e "[!] Secret not found in namespace $namespace"
        return 1
    fi

    NAME=$(jq -r '.metadata.name' <<<"$secret_json")
    TYPE=$(jq -r '.type' <<<"$secret_json")
    LABELS=$(jq -r '.metadata.labels | to_entries[] | "- \(.key): \(.value)"' <<<"$secret_json")
    ANNOTATIONS=$(jq -r '.metadata.annotations | to_entries[] | "- \(.key): \(.value)"' <<<"$secret_json")
    DATA_KEYS=$(jq -r '.data | to_entries[] | "- \(.key) (base64 encoded)"' <<<"$secret_json")

    local available_sections=(
        "Name"
        "Namespace"
        "Type"
        "Labels"
        "Annotations"
        "Data Keys"
    )

    local selected_sections
    selected_sections=$(printf "%s
" "${available_sections[@]}" \
        | fzf --multi --prompt="Select secret info to display: " --header="TAB to select multiple, ENTER for all")

    if [[ -z "$selected_sections" ]]; then
        selected_sections="all"
    fi

    show_section() {
        local key="$1"
        [[ "$selected_sections" == "all" || "$selected_sections" == *"$key"* ]]
    }

    echo ""
    show_section "Name" && echo "Name: $NAME"
    show_section "Namespace" && echo "Namespace: $namespace"
    show_section "Type" && echo "Type: $TYPE"

    if show_section "Labels"; then
        echo -e "
Labels:"
        [[ -z "$LABELS" ]] && echo "  > None" || echo "$LABELS"
    fi

    if show_section "Annotations"; then
        echo -e "
Annotations:"
        [[ -z "$ANNOTATIONS" ]] && echo "  > None" || echo "$ANNOTATIONS"
    fi

    if show_section "Data Keys"; then
        echo -e "
Data Keys (base64 encoded):"
        [[ -z "$DATA_KEYS" ]] && echo "  > None" || echo "$DATA_KEYS"
    fi

    echo -e "
[✓] Secret information retrieval completed."

    rm -f "$TMP_SECRET_JSON_FILE"
}

kget_configmap_info() {
    local namespace="$1"
    local configmap_name="$2"

    if [[ -z "$namespace" || -z "$configmap_name" ]]; then
        namespace=$(select_namespace) || return 1
        configmap_name=$(kubectl get configmap -n "$namespace" --no-headers -o custom-columns=":.metadata.name" | fzf --prompt="Select configmap: ") || return 1
    fi

    TMP_CM_JSON_FILE=$(mktemp)

    check_snipp "Fetching configmap '$configmap_name' in namespace '$namespace'" \
        "kubectl get configmap \"$configmap_name\" -n \"$namespace\" -o json > \"$TMP_CM_JSON_FILE\""

    cm_json=$(<"$TMP_CM_JSON_FILE")

    if [[ -z "$cm_json" ]]; then
        echo -e "[!] ConfigMap not found in namespace $namespace"
        return 1
    fi

    NAME=$(jq -r '.metadata.name' <<<"$cm_json")
    LABELS=$(jq -r '.metadata.labels | to_entries[] | "- \(.key): \(.value)"' <<<"$cm_json")
    ANNOTATIONS=$(jq -r '.metadata.annotations | to_entries[] | "- \(.key): \(.value)"' <<<"$cm_json")
    DATA=$(jq -r '.data | to_entries[] | "- \(.key): 
\(.value)
"' <<<"$cm_json")

    local available_sections=(
        "Name"
        "Namespace"
        "Labels"
        "Annotations"
        "Data"
    )

    local selected_sections
    selected_sections=$(printf "%s
" "${available_sections[@]}" \
        | fzf --multi --prompt="Select configmap info to display: " --header="TAB to select multiple, ENTER for all")

    if [[ -z "$selected_sections" ]]; then
        selected_sections="all"
    fi

    show_section() {
        local key="$1"
        [[ "$selected_sections" == "all" || "$selected_sections" == *"$key"* ]]
    }

    echo ""
    show_section "Name" && echo "Name: $NAME"
    show_section "Namespace" && echo "Namespace: $namespace"

    if show_section "Labels"; then
        echo -e "
Labels:"
        [[ -z "$LABELS" ]] && echo "  > None" || echo "$LABELS"
    fi

    if show_section "Annotations"; then
        echo -e "
Annotations:"
        [[ -z "$ANNOTATIONS" ]] && echo "  > None" || echo "$ANNOTATIONS"
    fi

    if show_section "Data"; then
        echo -e "
Data:"
        [[ -z "$DATA" ]] && echo "  > None" || echo "$DATA"
    fi

    echo -e "
[✓] ConfigMap information retrieval completed."

    rm -f "$TMP_CM_JSON_FILE"
}

kget_service_info() {
    local namespace="$1"
    local svc_name="$2"

    if [[ -z "$namespace" || -z "$svc_name" ]]; then
        namespace=$(select_namespace) || return 1
        svc_name=$(kubectl get svc -n "$namespace" --no-headers -o custom-columns=":.metadata.name" | fzf --prompt="Select service: ") || return 1
    fi

    TMP_SVC_JSON_FILE=$(mktemp)

    check_snipp "Fetching service '$svc_name' in namespace '$namespace'" \
        "kubectl get svc \"$svc_name\" -n \"$namespace\" -o json > \"$TMP_SVC_JSON_FILE\""

    svc_json=$(<"$TMP_SVC_JSON_FILE")

    if [[ -z "$svc_json" ]]; then
        echo -e "[!] Service not found in namespace $namespace"
        return 1
    fi

    NAME=$(jq -r '.metadata.name' <<<"$svc_json")
    TYPE=$(jq -r '.spec.type' <<<"$svc_json")
    CLUSTER_IP=$(jq -r '.spec.clusterIP' <<<"$svc_json")
    PORTS=$(jq -r '.spec.ports[] | "- Port: \(.port), Protocol: \(.protocol), TargetPort: \(.targetPort)"' <<<"$svc_json")
    SELECTOR=$(jq -r '.spec.selector // {} | to_entries[] | "- \(.key): \(.value)"' <<<"$svc_json")
    LABELS=$(jq -r '.metadata.labels | to_entries[] | "- \(.key): \(.value)"' <<<"$svc_json")
    ANNOTATIONS=$(jq -r '.metadata.annotations | to_entries[] | "- \(.key): \(.value)"' <<<"$svc_json")

    local available_sections=(
        "Name"
        "Namespace"
        "Type"
        "Cluster IP"
        "Ports"
        "Labels"
        "Annotations"
        "Selector"
    )

    local selected_sections
    selected_sections=$(printf "%s\n" "${available_sections[@]}" \
        | fzf --multi --prompt="Select service info to display: " --header="TAB to select multiple, ENTER for all")

    if [[ -z "$selected_sections" ]]; then
        selected_sections="all"
    fi

    show_section() {
        local key="$1"
        [[ "$selected_sections" == "all" || "$selected_sections" == *"$key"* ]]
    }

    echo ""
    show_section "Name" && echo "Name: $NAME"
    show_section "Namespace" && echo "Namespace: $namespace"
    show_section "Type" && echo "Type: $TYPE"
    show_section "Cluster IP" && echo "Cluster IP: $CLUSTER_IP"
    show_section "Ports" && echo -e "Ports:\n$PORTS"

    if show_section "Labels"; then
        echo -e "\nLabels:"
        [[ -z "$LABELS" ]] && echo "  > None" || echo "$LABELS"
    fi

    if show_section "Annotations"; then
        echo -e "\nAnnotations:"
        [[ -z "$ANNOTATIONS" ]] && echo "  > None" || echo "$ANNOTATIONS"
    fi

    if show_section "Selector"; then
        echo -e "\nSelector:"
        [[ -z "$SELECTOR" ]] && echo "  > None" || echo "$SELECTOR"
    fi

    echo -e "\n[✓] Service information retrieval completed."

    rm -f "$TMP_SVC_JSON_FILE"
}

kget_pv_info() {
    local pv_name="$1"

    if [[ -z "$pv_name" ]]; then
        pv_name=$(kubectl get pv --no-headers -o custom-columns=":.metadata.name" | fzf --prompt="Select PersistentVolume: ") || return 1
    fi

    TMP_PV_JSON_FILE=$(mktemp)

    check_snipp "Fetching persistent volume '$pv_name'" \
        "kubectl get pv \"$pv_name\" -o json > \"$TMP_PV_JSON_FILE\""

    pv_json=$(<"$TMP_PV_JSON_FILE")

    if [[ -z "$pv_json" ]]; then
        echo -e "[!] PersistentVolume not found"
        return 1
    fi

    NAME=$(jq -r '.metadata.name' <<<"$pv_json")
    STATUS=$(jq -r '.status.phase' <<<"$pv_json")
    CAPACITY=$(jq -r '.spec.capacity.storage' <<<"$pv_json")
    ACCESS_MODES=$(jq -r '.spec.accessModes[]' <<<"$pv_json" | paste -sd, -)
    STORAGE_CLASS=$(jq -r '.spec.storageClassName' <<<"$pv_json")
    RECLAIM_POLICY=$(jq -r '.spec.persistentVolumeReclaimPolicy' <<<"$pv_json")
    CLAIM_REF=$(jq -r '.spec.claimRef.namespace + "/" + .spec.claimRef.name' <<<"$pv_json" 2>/dev/null || echo "None")
    LABELS=$(jq -r '.metadata.labels | to_entries[] | "- \(.key): \(.value)"' <<<"$pv_json")
    ANNOTATIONS=$(jq -r '.metadata.annotations | to_entries[] | "- \(.key): \(.value)"' <<<"$pv_json")

    local available_sections=(
        "Name"
        "Status"
        "Capacity"
        "Access Modes"
        "Storage Class"
        "Reclaim Policy"
        "Claim Ref"
        "Labels"
        "Annotations"
    )

    local selected_sections
    selected_sections=$(printf "%s\n" "${available_sections[@]}" \
        | fzf --multi --prompt="Select PV info to display: " --header="TAB to select multiple, ENTER for all")

    if [[ -z "$selected_sections" ]]; then
        selected_sections="all"
    fi

    show_section() {
        local key="$1"
        [[ "$selected_sections" == "all" || "$selected_sections" == *"$key"* ]]
    }

    echo ""
    show_section "Name" && echo "Name: $NAME"
    show_section "Status" && echo "Status: $STATUS"
    show_section "Capacity" && echo "Capacity: $CAPACITY"
    show_section "Access Modes" && echo "Access Modes: $ACCESS_MODES"
    show_section "Storage Class" && echo "Storage Class: $STORAGE_CLASS"
    show_section "Reclaim Policy" && echo "Reclaim Policy: $RECLAIM_POLICY"
    show_section "Claim Ref" && echo "Bound PVC: $CLAIM_REF"

    if show_section "Labels"; then
        echo -e "\nLabels:"
        [[ -z "$LABELS" ]] && echo "  > None" || echo "$LABELS"
    fi

    if show_section "Annotations"; then
        echo -e "\nAnnotations:"
        [[ -z "$ANNOTATIONS" ]] && echo "  > None" || echo "$ANNOTATIONS"
    fi

    echo -e "\n[✓] PersistentVolume information retrieval completed."

    rm -f "$TMP_PV_JSON_FILE"
}

kget_pv_info() {
    local pv_name="$1"

    if [[ -z "$pv_name" ]]; then
        pv_name=$(kubectl get pv --no-headers -o custom-columns=":.metadata.name" | fzf --prompt="Select PersistentVolume: ") || return 1
    fi

    TMP_PV_JSON_FILE=$(mktemp)

    check_snipp "Fetching persistent volume '$pv_name'" \
        "kubectl get pv \"$pv_name\" -o json > \"$TMP_PV_JSON_FILE\""

    pv_json=$(<"$TMP_PV_JSON_FILE")

    if [[ -z "$pv_json" ]]; then
        echo -e "[!] PersistentVolume not found"
        return 1
    fi

    NAME=$(jq -r '.metadata.name' <<<"$pv_json")
    STATUS=$(jq -r '.status.phase' <<<"$pv_json")
    CAPACITY=$(jq -r '.spec.capacity.storage' <<<"$pv_json")
    ACCESS_MODES=$(jq -r '.spec.accessModes[]' <<<"$pv_json" | paste -sd, -)
    STORAGE_CLASS=$(jq -r '.spec.storageClassName' <<<"$pv_json")
    RECLAIM_POLICY=$(jq -r '.spec.persistentVolumeReclaimPolicy' <<<"$pv_json")
    CLAIM_REF=$(jq -r '.spec.claimRef.namespace + "/" + .spec.claimRef.name' <<<"$pv_json" 2>/dev/null || echo "None")
    LABELS=$(jq -r '.metadata.labels | to_entries[] | "- \(.key): \(.value)"' <<<"$pv_json")
    ANNOTATIONS=$(jq -r '.metadata.annotations | to_entries[] | "- \(.key): \(.value)"' <<<"$pv_json")

    local available_sections=(
        "Name"
        "Status"
        "Capacity"
        "Access Modes"
        "Storage Class"
        "Reclaim Policy"
        "Claim Ref"
        "Labels"
        "Annotations"
    )

    local selected_sections
    selected_sections=$(printf "%s\n" "${available_sections[@]}" \
        | fzf --multi --prompt="Select PV info to display: " --header="TAB to select multiple, ENTER for all")

    if [[ -z "$selected_sections" ]]; then
        selected_sections="all"
    fi

    show_section() {
        local key="$1"
        [[ "$selected_sections" == "all" || "$selected_sections" == *"$key"* ]]
    }

    echo ""
    show_section "Name" && echo "Name: $NAME"
    show_section "Status" && echo "Status: $STATUS"
    show_section "Capacity" && echo "Capacity: $CAPACITY"
    show_section "Access Modes" && echo "Access Modes: $ACCESS_MODES"
    show_section "Storage Class" && echo "Storage Class: $STORAGE_CLASS"
    show_section "Reclaim Policy" && echo "Reclaim Policy: $RECLAIM_POLICY"
    show_section "Claim Ref" && echo "Bound PVC: $CLAIM_REF"

    if show_section "Labels"; then
        echo -e "\nLabels:"
        [[ -z "$LABELS" ]] && echo "  > None" || echo "$LABELS"
    fi

    if show_section "Annotations"; then
        echo -e "\nAnnotations:"
        [[ -z "$ANNOTATIONS" ]] && echo "  > None" || echo "$ANNOTATIONS"
    fi

    echo -e "\n[✓] PersistentVolume information retrieval completed."

    rm -f "$TMP_PV_JSON_FILE"
}

kget_pvc_info() {
    local namespace="$1"
    local pvc_name="$2"

    if [[ -z "$namespace" || -z "$pvc_name" ]]; then
        namespace=$(select_namespace) || return 1
        pvc_name=$(kubectl get pvc -n "$namespace" --no-headers -o custom-columns=":.metadata.name" | fzf --prompt="Select PersistentVolumeClaim: ") || return 1
    fi

    TMP_PVC_JSON_FILE=$(mktemp)

    check_snipp "Fetching persistent volume claim '$pvc_name' in namespace '$namespace'" \
        "kubectl get pvc \"$pvc_name\" -n \"$namespace\" -o json > \"$TMP_PVC_JSON_FILE\""

    pvc_json=$(<"$TMP_PVC_JSON_FILE")

    if [[ -z "$pvc_json" ]]; then
        echo -e "[!] PersistentVolumeClaim not found in namespace $namespace"
        return 1
    fi

    NAME=$(jq -r '.metadata.name' <<<"$pvc_json")
    STATUS=$(jq -r '.status.phase' <<<"$pvc_json")
    VOLUME=$(jq -r '.spec.volumeName' <<<"$pvc_json")
    CAPACITY=$(jq -r '.status.capacity.storage' <<<"$pvc_json")
    ACCESS_MODES=$(jq -r '.status.accessModes[]' <<<"$pvc_json" | paste -sd, -)
    STORAGE_CLASS=$(jq -r '.spec.storageClassName' <<<"$pvc_json")
    LABELS=$(jq -r '.metadata.labels | to_entries[] | "- \(.key): \(.value)"' <<<"$pvc_json")
    ANNOTATIONS=$(jq -r '.metadata.annotations | to_entries[] | "- \(.key): \(.value)"' <<<"$pvc_json")

    local available_sections=(
        "Name"
        "Namespace"
        "Status"
        "Volume"
        "Capacity"
        "Access Modes"
        "Storage Class"
        "Labels"
        "Annotations"
    )

    local selected_sections
    selected_sections=$(printf "%s\n" "${available_sections[@]}" \
        | fzf --multi --prompt="Select PVC info to display: " --header="TAB to select multiple, ENTER for all")

    if [[ -z "$selected_sections" ]]; then
        selected_sections="all"
    fi

    show_section() {
        local key="$1"
        [[ "$selected_sections" == "all" || "$selected_sections" == *"$key"* ]]
    }

    echo ""
    show_section "Name" && echo "Name: $NAME"
    show_section "Namespace" && echo "Namespace: $namespace"
    show_section "Status" && echo "Status: $STATUS"
    show_section "Volume" && echo "Bound PV: $VOLUME"
    show_section "Capacity" && echo "Capacity: $CAPACITY"
    show_section "Access Modes" && echo "Access Modes: $ACCESS_MODES"
    show_section "Storage Class" && echo "Storage Class: $STORAGE_CLASS"

    if show_section "Labels"; then
        echo -e "\nLabels:"
        [[ -z "$LABELS" ]] && echo "  > None" || echo "$LABELS"
    fi

    if show_section "Annotations"; then
        echo -e "\nAnnotations:"
        [[ -z "$ANNOTATIONS" ]] && echo "  > None" || echo "$ANNOTATIONS"
    fi

    echo -e "\n[✓] PersistentVolumeClaim information retrieval completed."

    rm -f "$TMP_PVC_JSON_FILE"
}

kget_pods_sort_by() {

    local namespace="$1"
    local sort_option

    if [ -z "$namespace" ]; then
        namespace=$(select_namespace)
    fi

    if [[ -z "$namespace" ]]; then
        namespace=$(kubectl get ns --no-headers | awk '{print $1}' | fzf --prompt "Select Namespace: ")
    fi

    if [[ -z "$namespace" ]]; then
        echo "No namespace selected. Exiting..."
        return 1
    fi
    echo -e "\n${LIGHT_YELLOW}Namespace sélectionné:${RESET} $namespace\n"
    sort_option=$(echo -e "Status\nAge Asc\nAge Desc\nName Asc\nName Desc\nrestart asc" | fzf --prompt "Sort by: ")

    case "$sort_option" in
        "Status") kubectl get po -n "$namespace" --no-headers | sort -k3 | column -t ;;
        "Age Asc") kubectl get po -n "$namespace" --no-headers | sort -k5n | column -t ;;
        "Age Desc") kubectl get po -n "$namespace" --no-headers | sort -k5nr | column -t ;;
        "Name Asc") kubectl get po -n "$namespace" --no-headers | sort -k1 | column -t ;;
        "Name Desc") kubectl get po -n "$namespace" --no-headers | sort -rk1 | column -t ;;
        "restart asc") kubectl get po -n "$namespace" --no-headers | awk '$4 != "0"' | sort -rk4 | column -t ;;
        *) echo "Invalid option selected." ;;
    esac
}

kget_pods_not_running() {
    # kubectl get po -A | grep -v "Running\|Completed"
    local YELLOW="\033[1;33m"
    local RESET="\033[0m"
    local apply_filter exclude_pattern pod_info pod_name namespace

    read -r -p "Exclude pods by pattern? (y/n): " apply_filter

    if [[ "$apply_filter" == "y" ]]; then
        read -r -p "Pattern to exclude: " exclude_pattern
        kubectl get pods -A --no-headers | grep -vE "Running|Completed" | grep -v "$exclude_pattern"
    else
        kubectl get pods -A --no-headers | grep -vE "Running|Completed"
    fi
}

kget_pods_logs() {
    local YELLOW="\033[1;33m"
    local RESET="\033[0m"
    local apply_filter exclude_pattern pod_info pod_name namespace

    read -r -p "Exclude pods by pattern? (y/n) : " apply_filter

    if [[ "$apply_filter" == "y" ]]; then
        read -r -p "Pattern to exclude: " exclude_pattern
        pod_info=$(kubectl get pods -A --no-headers | grep -vE "Running|Completed" | grep -v "$exclude_pattern" | fzf --prompt="Select a pod: ") || return
    else
        pod_info=$(kubectl get pods -A --no-headers | grep -vE "Running|Completed" | fzf --prompt="Select a pod: ") || return
    fi

    namespace=$(awk '{print $1}' <<<"$pod_info")
    pod_name=$(awk '{print $2}' <<<"$pod_info")

    echo -e "\n${YELLOW}--- Logs for Pod: $pod_name (Namespace: $namespace) ---${RESET}"
    echo "------------------------------------------------------------------"

    if [[ -n "$pod_name" && -n "$namespace" ]]; then
        local TMP_LOG_FILE="/tmp/${pod_name}_logs.txt"

        check_snipp "Fetching logs for pod '$pod_name' in namespace '$namespace'" \
            "kubectl logs -n \"$namespace\" \"$pod_name\" --all-containers=true > \"$TMP_LOG_FILE\" 2>/dev/null"

        echo -e "\n${YELLOW}Logs saved to: $TMP_LOG_FILE${RESET}"

        open_with_editor "$TMP_LOG_FILE"
    fi
}

# Include PV/PVC info
