#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
kubectl_get_pod_config() {
    local NAMESPACE="${1:-}"
    local POD_NAME="${2:-}"

    ensure_pod_and_namespace "$NAMESPACE" "$POD_NAME" || return 1

    local FILE
    FILE=$(create_temp_file "_pod_${POD_NAME}_${NAMESPACE}.yaml")

    if kubectl get -n "$NAMESPACE" pod "$POD_NAME" -o yaml >"$FILE" 2>/dev/null; then
        open_yaml_output "$FILE" "Pod - $POD_NAME - Namespace - $NAMESPACE"
    else
        echo -e "${RED}❌ Failed to retrieve Pod config for '$POD_NAME' in namespace '$NAMESPACE'.${NC}"
        rm -f "$FILE"
        return 1
    fi
}

kubectl_get_svc_config() {
    ensure_svc_and_namespace || return 1
    local FILE
    FILE=$(create_temp_file "_svc_${SVC_NAME}_${NAMESPACE}.yaml")
    kubectl get -n "$NAMESPACE" services "$SVC_NAME" -o yaml >"$FILE" 2>/dev/null
    open_yaml_output "$FILE" "Service - $SVC_NAME - Namespace - $NAMESPACE"
}

kubectl_get_ingresses_config() {
    ensure_ingresse_and_namespace || return 1

    local FILE
    DATE_STR=$(date '+%Y%m%d_%H%M%S')
    FILE=$(create_temp_file "_ingress_${INGRESSE_NAME}_${NAMESPACE}_${DATE_STR}.yaml")

    trap 'rm -f "$FILE"' EXIT

    kubectl -n "$NAMESPACE" get ingress "$INGRESSE_NAME" -o yaml >"$FILE"

    open_yaml_output "$FILE" "Ingress - $INGRESSE_NAME - Namespace - $NAMESPACE"
}

kubectl_get_configmap_config() {
    ensure_configmap_and_namespace || return 1
    local FILE
    FILE=$(create_temp_file "_configmap_${CONFIGMAP_NAME}_${NAMESPACE}.yaml")
    kubectl -n "$NAMESPACE" get configmap "$CONFIGMAP_NAME" -o yaml >"$FILE" 2>/dev/null
    open_yaml_output "$FILE" "ConfigMap - $CONFIGMAP_NAME - Namespace - $NAMESPACE"
}

kubectl_get_deployment_config() {
    ensure_deployment_and_namespace || return 1
    local FILE
    FILE=$(create_temp_file "_deployment_${DEPLOYMENT_NAME}_${NAMESPACE}.yaml")
    kubectl -n "$NAMESPACE" get deployment "$DEPLOYMENT_NAME" -o yaml >"$FILE" 2>/dev/null
    open_yaml_output "$FILE" "Deployment - $DEPLOYMENT_NAME - Namespace - $NAMESPACE"
}

kubectl_get_statefulsets_config() {
    ensure_statefulsets_and_namespace || return 1
    local FILE
    FILE=$(create_temp_file "_statefulset_${STATEFULSET_NAME}_${NAMESPACE}.yaml")
    kubectl -n "$NAMESPACE" get statefulset "$STATEFULSET_NAME" -o yaml >"$FILE" 2>/dev/null
    open_yaml_output "$FILE" "StatefulSet - $STATEFULSET_NAME - Namespace - $NAMESPACE"
}

kubectl_get_daemonset_config() {
    ensure_daemonset_and_namespace || return 1
    local FILE
    FILE=$(create_temp_file "_daemonset_${DAEMONSET_NAME}_${NAMESPACE}.yaml")
    kubectl -n "$NAMESPACE" get daemonset "$DAEMONSET_NAME" -o yaml >"$FILE" 2>/dev/null
    open_yaml_output "$FILE" "DaemonSet - $DAEMONSET_NAME - Namespace - $NAMESPACE"
}

kget_pvc_info() {
    # Check if at least one argument is provided
    if [ "$#" -lt 1 ]; then
        echo "Usage: $0 {pod_bound|pod_no_bound} [{names_only|pvc_detailed}]"
        return 1
    fi

    # Determine the phase based on the first argument
    local phase
    case $1 in
        pod_bound)
            phase="Bound"
            ;;
        pod_no_bound)
            phase="Pending"
            ;;
        *)
            echo "Invalid argument. Use 'pod_bound' or 'pod_no_bound'."
            return 1
            ;;
    esac

    # Get PVCs based on the specified phase and store in a JSON variable
    local pvc_json
    pvc_json=$(kubectl get pvc --all-namespaces -o json 2>/dev/null | jq -r "
      .items[] |
      select(.status.phase == \"$phase\") |
      {
        name: .metadata.name,
        kind: .kind,
        creationTimestamp: .metadata.creationTimestamp,
        ownerReferences: {
          name: .metadata.ownerReferences[0].name,
          kind: .metadata.ownerReferences[0].kind
        },
        accessModes: .spec.accessModes,
        storage: .spec.resources.requests.storage,
        volumeMode: .spec.volumeMode,
        status: {
          phase: .status.phase
        }
      }
    ")
    #max_name_length=$(kubectl get pvc --all-namespaces -o json 2>/dev/null | jq -r "
    #  .items[] | .metadata.name" | awk '{ if (length > max) max = length } END { print max }')
    #
    #max_name_length=$((max_name_length < 20 ? 20 : max_name_length))
    #
    #pvc_json=$(kubectl get pvc --all-namespaces -o json 2>/dev/null | jq -r "
    #  .items[] |
    #  select(.status.phase == \"$phase\") |
    #  [
    #    .metadata.name,
    #    .kind,
    #    .metadata.creationTimestamp,
    #    (.spec.accessModes // [\"N/A\"] | join(\",\")),
    #    (.spec.resources.requests.storage // \"N/A\"),
    #    (.spec.volumeMode // \"N/A\"),
    #    .status.phase
    #  ] | @tsv
    #")
    #
    #printf "%-${max_name_length}s %-10s %-25s %-15s %-10s %-15s %-10s\n" \
    #      "Name" "Kind" "Creation Timestamp" "Access Modes" "Storage" "Volume Mode" "Phase"
    #
    #echo "$pvc_json" | while IFS=$'\t' read -r name kind creationTimestamp accessModes storage volumeMode phase; do
    #    printf "%-${max_name_length}s %-10s %-25s %-15s %-10s %-15s %-10s\n" \
    #          "$name" "$kind" "$creationTimestamp" "$accessModes" "$storage" "$volumeMode" "$phase"
    #done
    # Check if any PVCs were found
    if [[ -z "$pvc_json" ]]; then
        echo "No PVCs found with status '$phase'."
        return 0
    fi

    # Determine the output format based on the second argument
    local detail_mode
    detail_mode=${2:-"names_only"} # Default to "names_only" if not provided

    if [[ "$detail_mode" == "names_only" ]]; then
        # Display PVC names with their status
        echo "PVCs with status '$phase':"
        echo "$pvc_json" | jq -r '.name + " (status: " + .status.phase + ")"'
    else
        # Loop through each PVC JSON object and extract detailed information
        echo "$pvc_json" | jq -c '.' | while IFS= read -r pvc; do
            local name kind creationTimestamp ownerName ownerKind accessModes storage volumeMode status

            name=$(echo "$pvc" | jq -r '.name')
            kind=$(echo "$pvc" | jq -r '.kind')
            creationTimestamp=$(echo "$pvc" | jq -r '.creationTimestamp')
            ownerName=$(echo "$pvc" | jq -r '.ownerReferences.name')
            ownerKind=$(echo "$pvc" | jq -r '.ownerReferences.kind')
            accessModes=$(echo "$pvc" | jq -r '.accessModes | join(", ")')
            storage=$(echo "$pvc" | jq -r '.storage')
            volumeMode=$(echo "$pvc" | jq -r '.volumeMode')
            status=$(echo "$pvc" | jq -r '.status.phase')

            # Echo the detailed information
            echo "Name: $name"
            echo "Kind: $kind"
            echo "Creation Timestamp: $creationTimestamp"
            echo "Owner Name: $ownerName"
            echo "Owner Kind: $ownerKind"
            echo "Access Modes: $accessModes"
            echo "Storage: $storage"
            echo "Volume Mode: $volumeMode"
            echo "Status Phase: $status"
            echo "-----------------------------------------"
        done
    fi
}

k8s_get_matching_configmaps() {
    local namespace="$1"
    local search_string="$2"

    if [ -z "$NAMESPACE" ] || [ -z "$search_string" ]; then
        k8s_get_matching_secrets_display_help
    fi

    kubectl get configmaps -n "$NAMESPACE" --no-headers | awk '{print $1}' | while read -r cm_name; do
        kubectl get cm "$cm_name" -n "$NAMESPACE" -o yaml | grep "$search_string"
    done
}

k8s_get_matching_secrets_display_help() {
    echo "Usage: ${FUNCNAME[0]} <namespace> <search_string>"
    echo "  <namespace>      The namespace to search in."
    echo "  <search_string>  The string to search for in secrets or configmaps."
    echo
    echo " example: ${FUNCNAME[0]} \"logging\" \"match kubernetes\""
    exit 1
}
# Secret masking
