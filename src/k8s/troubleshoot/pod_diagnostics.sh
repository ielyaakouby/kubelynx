#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
# 1. Identify the Affected Pod and Namespace
function identify_affected_pod_and_namespace() {
    namespace=$1
    pod_name=$2
    if [[ -z $namespace ]]; then
        namespace=$(select_namespace) || exit 1
        if [[ -z $namespace ]]; then
            echo -e "namespace is empty. Exiting..."
            return 1
        fi
        frame_message_1 "${GREEN}" "[✓] Selected Namespace: $namespace"
    fi
    if [[ -n $pod_name ]]; then
        echo "----------------------------------------"
        echo "Processing pod: ${pod_name}"
        echo "----------------------------------------"
        check_pod_details "${namespace}" "${pod_name}"
    else
        pods=$(kubectl get pods -n "${namespace}" --no-headers 2>/dev/null | grep -vE "Running|Completed")
        pod_list=$(echo "$pods" | awk '{print $1}')
        pod_list_with_all=$(echo -e "All Pods\n$(echo "$pods" | awk '{print $1}')")

        if [[ -z "${pods}" ]]; then
            echo -e "All pods in namespace ${namespace} are running. No issues detected."
            return 0
        else
            echo -e "Affected pods (not running) in namespace ${namespace}:"
            echo -e "\n${pods}" | boxes -d stone
            #return 1
        fi
        echo
        read -rp "" choice
        selected_pod=$(echo "$pod_list_with_all" | fzf --prompt="Select a pod: " --height=10 --border)
        if [ "$selected_pod" == "All Pods" ]; then
            echo "Processing all pods in namespace '${namespace}'..."
            echo "$pod_list" | while read -r pod; do
                echo "------------------------------------------------"
                echo "Processing pod: ${pod}"
                echo "------------------------------------------------"
                check_pod_details "${namespace}" "${pod}"
            done
        elif [ -n "$selected_pod" ]; then
            echo "------------------------------------------------"
            echo "Processing selected pod: $selected_pod"
            echo "------------------------------------------------"
            check_pod_details "${namespace}" "${selected_pod}"
        else
            echo "No pod selected."
        fi
    fi

}

# 2. Check Pod Details
function check_pod_details() {
    namespace=$1
    pod_name=$2
    if [[ -z "$pod_name" ]] || [[ -z $namespace ]]; then
        namespace=$(select_namespace) || exit 1
        pod_name=$(select_pod $namespace) || exit 1
        if [[ -z $namespace || -z "$pod_name" ]]; then
            echo -e "namespace and/or pod name is empty. Exiting..."
            return 1
        fi
        frame_message_1 "${GREEN}" "[✓] Selected Namespace: $namespace"
        frame_message_1 "${GREEN}" "[✓] Selected Pod: $pod_name"
    fi
    if [[ "${pod_name}" != "All Pods" ]]; then
        pod_description=$(kubectl describe pod "${pod_name}" -n "${namespace}" 2>/dev/null)
        if [[ -z "${pod_description}" ]]; then
            echo -e "  [describe] Failed to retrieve pod details for ${pod_name} in namespace ${namespace}. Pod may not exist."
            return 1
        fi
    fi
    pod_description_errors="$(kubectl -n "$namespace" get events --field-selector involvedObject.kind=Pod,involvedObject.name="$pod_name" -o json 2>/dev/null | jq '.items[] | select(.type != "Normal")')"
    if [[ -n $pod_description_errors ]]; then
        echo -e "${LIGHT_RED}  [events] problem in ${pod_name} - namespace ${namespace}${RESET}"
    fi
    pod_status=$(kubectl get pod "${pod_name}" -n "${namespace}" -o jsonpath='{.status.phase}' 2>/dev/null)
    containers_ready=$(kubectl get pod "${pod_name}" -n "${namespace}" -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null)

    if [[ "$pod_status" == "Running" && "$containers_ready" == "true" ]]; then
        echo "  [check pod status] Pod '${pod_name}' is running and ready. Checking backend connectivity..."
    else
        echo -e "${LIGHT_RED}  [check pod status] Pod '${pod_name}' is not running or not all containers are ready. ${RESET}"
    fi
    check_pod_logs ${namespace} ${pod_name}
}

# 3. View Pod Logs

function check_pod_logs() {
    namespace=$1
    pod_name=$2

    logs=$(kubectl logs "${pod_name}" -n "${namespace}" 2>/dev/null)
    logs2=$(echo ${logs} | grep -Ei "Error|Failed|ImagePullBackOff|CrashLoopBackOff|OOMKilled|Connection refused" >/dev/null)

    if echo -e "${logs}" | grep -Ei "Error|Failed|CrashLoopBackOff|OOMKilled|Connection refused" >/dev/null; then
        echo -e "${LIGHT_RED}  [logs] Error detected in ${pod_name} - namespace ${namespace}${RESET}"
    else
        echo -e "${LIGHT_GREEN}  [logs] No errors detected in the logs for ${pod_name}. ${RESET}"
    fi
    check_deployment_replica_set_stateful_set_configuration "${namespace}" "${pod_name}"
}

function view_pod_logs() {
    pod_name=$2
    namespace=$1

    logs=$(kubectl logs "${pod_name}" -n "${namespace}" 2>/dev/null)
    logs2=$(echo ${logs} | grep -Ei "Error|CrashLoopBackOff|OOMKilled|Connection refused" >/dev/null)

    if echo -e "${logs}" | grep -Ei "Error|CrashLoopBackOff|OOMKilled|Connection refused" >/dev/null; then
        echo -e "${LIGHT_RED}Error detected in ${pod_name} - namespace ${namespace} ${logs2} ${RESET}"
    else
        echo -e "${LIGHT_GREEN}[logs] No errors detected in the logs for ${pod_name}. ${RESET}"
    fi
    check_deployment_replica_set_stateful_set_configuration "${namespace}" "${pod_name}"
}
# 4. Check Deployment/ReplicaSet/StatefulSet Configuration
function check_deployment_replica_set_stateful_set_configuration() {
    pod_name=$2
    namespace=$1

    owner_kind=$(kubectl get pod "${pod_name}" -n "${namespace}" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null)
    owner=$(kubectl get pod "${pod_name}" -n "${namespace}" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null)
    if [[ -z "${owner}" ]]; then
        echo -e "${LIGHT_RED}  [check resource config] Failed to identify the owner (deployment/replicaset/statefulset) of pod ${pod_name}. ${RESET}"
    else
        if [[ $owner_kind == "Job" ]]; then
            owner_details=$(kubectl get jobs "${owner}" -n "${namespace}" -o yaml 2>/dev/null)
        else

            owner_details=$(kubectl get deployment "${owner}" -n "${namespace}" -o yaml 2>/dev/null \
                || kubectl get replicaset "${owner}" -n "${namespace}" -o yaml 2>/dev/null \
                || kubectl get statefulset "${owner}" -n "${namespace}" -o yaml 2>/dev/null)

            if [[ -z "${owner_details}" ]]; then
                echo -e "${LIGHT_RED}[check resource config] Failed to retrieve details for ${owner} in namespace ${namespace}. ${RESET}"
            fi
        fi
    fi

    verify_events_in_namespace "${namespace}" "${pod_name}"
}

function verify_events_in_namespace() {
    namespace=${1:-$(select_namespace)} || exit 1
    pod_name=${2:-$(select_pod "$namespace")} || exit 1

    events=$(kubectl get events -n "$namespace" --sort-by='.metadata.creationTimestamp' 2>/dev/null)
    pod_events_json=$(kubectl -n "$namespace" get events --field-selector involvedObject.kind=Pod,involvedObject.name="$pod_name" -o json | jq '.items[] | select(.type != "Normal")')
    critical_events=$(echo "$events" | grep -Ei "Error|Failed|Warning" 2>/dev/null)

    if [[ -z "$events" ]]; then
        echo -e "${LIGHT_RED}  [Namespace Events] No events found in namespace ${namespace}.${RESET}"
    elif [[ -n "$critical_events" ]]; then
        echo -e "${LIGHT_RED}  [Namespace Events] Critical issues detected in namespace '${namespace}':${RESET}"
    else
        echo -e "${LIGHT_GREEN}[Namespace Events] No critical errors in namespace events.${RESET}"
    fi

    if [[ -z "$pod_events_json" ]]; then
        echo -e "${LIGHT_RED}  [Pod Events] No events found for pod '${pod_name}' in namespace ${namespace}.${RESET}"
    elif echo "$critical_events" | grep -qE "Error|Failed|Warning"; then
        echo -e "${LIGHT_RED}  [Pod Events] Critical issues detected for pod '${pod_name}' in namespace '${namespace}':${RESET}"
        #echo "$critical_events"
    else
        echo -e "${LIGHT_GREEN}  [Pod Events] No critical errors in pod events.${RESET}"
    fi

    node_name=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.spec.nodeName}' 2>/dev/null)

    if [[ -z "$node_name" || "$node_name" == "<none>" ]]; then
        echo -e "${LIGHT_RED}Pod '${pod_name}' is not scheduled on any node (it may be pending).${RESET}"
        verify_liveness_readiness_probes "$namespace" "$pod_name"
    else
        check_node_status_and_resources "$node_name"
    fi
}

# 6. Check Node Status and Resources
function check_node_status_and_resources() {
    node_name=$1

    if [[ -z "$node_name" ]]; then
        node_name=$(select_node_name) || exit 1
        if [[ -z $node_name ]]; then
            echo -e "node_name is empty. Exiting..."
            return 1
        fi
        frame_message "${GREEN}" "Selected node_name : $namespace"
    fi

    node_details=$(kubectl describe node "${node_name}" 2>/dev/null)
    node_details2=$(echo $node_details | grep -Ei "MemoryPressure|DiskPressure|PIDPressure" 2>/dev/null)

    if [[ -z "${node_details}" ]]; then
        echo -e "${LIGHT_RED}  [check node status] Failed to retrieve details for node ${node_name}. ${RESET}"
        if echo -e "${node_details2}" | grep -Ei "MemoryPressure|DiskPressure|PIDPressure" >/dev/null; then
            echo -e "${LIGHT_RED}  [check node status] Node ${node_name} is experiencing resource pressure. Investigate further.\n Node details for ${node_name} ${RESET}"
        else
            echo -e "${LIGHT_GREEN}[check node status] Node resources appear normal. Checking liveness/readiness probes... ${RESET}"
        fi
    fi
    verify_liveness_readiness_probes "${namespace}" "${pod_name}"
}

# 7. Verify Liveness/Readiness Probes
function verify_liveness_readiness_probes() {
    pod_name=$2
    namespace=$1

    liveness_configured=$(kubectl get pod "${pod_name}" -n "${namespace}" -o jsonpath='{.spec.containers[*].livenessProbe}' 2>/dev/null)
    readiness_configured=$(kubectl get pod "${pod_name}" -n "${namespace}" -o jsonpath='{.spec.containers[*].readinessProbe}' 2>/dev/null)

    if [[ -n "$liveness_configured" || -n "$readiness_configured" ]]; then
        pod_description=$(kubectl describe pod "${pod_name}" -n "${namespace}" 2>/dev/null)

        if [[ -n "$liveness_configured" ]]; then
            pod_description_liveness_failed=$(echo "$pod_description" | grep -i "Liveness probe failed" 2>/dev/null)
            if [[ -n "$pod_description_liveness_failed" ]]; then
                echo "  [check liveness] Liveness probe failed in pod ${pod_name}"
            fi
        fi

        if [[ -n "$readiness_configured" ]]; then
            pod_description_readiness_failed=$(echo "$pod_description" | grep -i "Readiness probe failed" 2>/dev/null)
            if [[ -n "$pod_description_readiness_failed" ]]; then
                echo "  [check readiness] Readiness probe failed in pod ${pod_name}"

            fi
        fi
    else
        echo -e "${LIGHT_GREEN}  [check readiness & liveness] No liveness or readiness probes are configured for pod '${pod_name}' in namespace '${namespace}'. ${RESET}"
    fi
    inspect_application_configuration_and_dependencies "${namespace}" "${pod_name}"
}

# 8. Inspect Application Configuration and Dependencies
function inspect_application_configuration_and_dependencies() {
    pod_name=$2
    namespace=$1

    check_ingress_configuration "${namespace}" "${pod_name}"
}

# 9. Check Ingress Configuration
function check_ingress_configuration() {
    pod_name=$2
    namespace=$1

    ingresses=$(kubectl get ingress -n "${namespace}" --no-headers 2>/dev/null)
    if [[ -z "${ingresses}" ]]; then
        echo -e "${LIGHT_GREEN}  [check ingress] No ingress resources found in namespace ${namespace}. If external access is expected, check ingress setup. ${RESET}"
    else
        for ingress in $(kubectl get ingress -n "${namespace}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
            ingress_details=$(kubectl describe ingress "${ingress}" -n "${namespace}" 2>/dev/null)

            if echo -e "${ingress_details}" | grep -Ei "Host not found|Timeout|Connection refused" >/dev/null; then
                echo -e "${LIGHT_RED}  [check ingress] Ingress issue detected. Please check ingress rules, service backend, and DNS settings. ${RESET}"
            fi
        done
    fi

    pod_status=$(kubectl get pod "${pod_name}" -n "${namespace}" -o jsonpath='{.status.phase}' 2>/dev/null)
    containers_ready=$(kubectl get pod "${pod_name}" -n "${namespace}" -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null)

    if [[ "$pod_status" == "Running" && "$containers_ready" == "true" ]]; then
        check_backend_connectivity "${namespace}" "${pod_name}"
    else
        check_pod_network_issues "${namespace}" "${pod_name}"
    fi
}

# 10. Check Backend Connectivity
function check_backend_connectivity() {
    pod_name=$2
    namespace=$1
    backend_url=${3:-}

    if [[ -z "$backend_url" ]]; then
        get_pods_corresponding_service_url $namespace $pod_name
        read -rp "Enter backend service url : " backend_url
    fi
    response_code=$(kubectl exec -it "${pod_name}" -n "${namespace}" -- curl -s -o /dev/null -w "%{http_code}" "${backend_url}" 2>/dev/null)

    if [[ "${response_code}" -ne 200 ]]; then
        echo -e "${LIGHT_RED}  [check backend connectivity] Backend connectivity issue detected. Response code: ${response_code}. Please check the backend service and its configuration. ${RESET}"
        #return 1
    else
        echo -e "${LIGHT_GREEN}  [check backend connectivity] Backend connectivity is working correctly. Proceeding to check network issues... ${RESET}"
    fi

    pod_status=$(kubectl get pod "${pod_name}" -n "${namespace}" -o jsonpath='{.status.phase}' 2>/dev/null)
    containers_ready=$(kubectl get pod "${pod_name}" -n "${namespace}" -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null)

    if [[ "$pod_status" == "Running" && "$containers_ready" == "true" ]]; then
        echo "  [check backend connectivity] Pod '${pod_name}' is running and ready. Checking external network connectivity..."
        check_pod_network_issues "${namespace}" "${pod_name}"
    fi
}

get_pods_corresponding_service_url() {
    namespace="$1"
    pod_name="$2"
    if [[ -z "$pod_name" ]]; then
        echo -e "${RED}Pod name is empty. Exiting...${RESET}"
        return 1
    fi

    echo -e "${BLUE}Labels for Pod '$pod_name':${RESET}"
    label_string=$(kubectl -n "${namespace}" get pod "${pod_name}" --show-labels --no-headers 2>/dev/null | awk '{print $NF}' | tr -d '{}"')

    if [[ -z "$label_string" ]]; then
        echo -e "${RED}No labels found for pod ${pod_name} in namespace ${namespace}.${RESET}"
        return 1
    fi

    echo -e "${YELLOW}Finding the corresponding services for pod '$pod_name'...${RESET}"
    echo -e "${GREEN}Found service:\n${RESET}"

    echo "$label_string" | tr ',' '\n' | while read -r label; do
        kubectl -n "${namespace}" get services --no-headers -l "$label" 2>/dev/null | awk '{print $1}' | sort -u
    done | sort -u | while read -r service; do
        service_url="${service}.${namespace}.svc.cluster.local"
        echo $service_url
    done
    echo
}

# 11. Check for Pod Network Issues
check_pod_network_issues() {
    local namespace="${1:-}"
    local pod_name="${2:-}"
    local target_url="${3:-}"

    if [[ -z "$namespace" ]]; then
        namespace=$(select_namespace) || return 1
        [[ -z "$namespace" ]] && echo "Namespace is empty. Exiting..." && return 1
        frame_message_1 "${GREEN}" "[✓] Selected Namespace: $namespace"
    fi

    if [[ -z "$pod_name" ]]; then
        pod_name=$(select_pod "$namespace") || return 1
        [[ -z "$pod_name" ]] && echo "Pod name is empty. Exiting..." && return 1
        frame_message_1 "${GREEN}" "[✓] Selected Pod: $pod_name"
    fi

    if [[ -z "$target_url" ]]; then
        target_url="https://google.com"
    fi

    if kubectl exec -it "$pod_name" -n "$namespace" -- sh -c "ls / > /dev/null 2>&1" 2>/dev/null; then
        response_code=$(kubectl exec -it "$pod_name" -n "$namespace" -- curl -s -o /dev/null -w "%{http_code}" "$target_url" 2>/dev/null)

        if [[ "$response_code" != "200" ]]; then
            echo -e "${LIGHT_RED}  [check network issues] Network issue detected. Response code: ${response_code}. Please check network policies. ${RESET}"
        else
            echo -e "${LIGHT_GREEN}  [check network issues] No network issues detected. Monitoring pod... ${RESET}"
        fi
    else
        echo -e "${LIGHT_YELLOW}  [check network issues] Cannot exec into pod ${pod_name}. Skipping network check. ${RESET}"
    fi
}

# 12. Monitor the Pod After Fixing Issues
function monitor_pod_after_applying_fixes() {
    namespace=$1
    if [[ -z $namespace ]]; then
        namespace=$(select_namespace) || exit 1
        if [[ -z $namespace ]]; then
            echo -e "namespace is empty. Exiting..."
            return 1
        fi
        frame_message_1 "${GREEN}" "[✓] Selected Namespace: $namespace"
    fi
    kubectl get pods -n "${namespace}" -w 2>/dev/null
}

select_action_menu() {
    local pod_name=$2
    local namespace=$1
    if [[ -z $namespace ]]; then
        namespace=$(select_namespace) || exit 1
        if [[ -z $namespace ]]; then
            echo -e "namespace name is empty. Exiting..."
            return 1
        fi
        frame_message_1 "${GREEN}" "[✓] Selected Namespace: $namespace"
    fi
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    NC='\033[0m' # No Color

    while true; do
        options=(
            "Quit"
            "Identify Affected Pod and Namespace"
            "Check Pod Details"
            "View Pod Logs"
            "Check Liveness and Readiness Probes"
            "Check Ingress Configuration"
            "Check Backend Connectivity"
            "Monitor Pod After Applying Fixes"
            "Quit"
        )
        selected_action=$(printf "%s\n" "${options[@]}" \
            | fzf --prompt="Select an option: " \
                --header="" \
                --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,header:#FFFFFF,prompt:#FFD700" \
                --height=50%)
        if [ "$selected_action" == "Exit" ]; then
            frame_message "${GREEN}" "Exiting the menu \"select action menu\""
            break
        fi

        case $selected_action in
            "Identify Affected Pod and Namespace")
                identify_affected_pod_and_namespace "${namespace}"
                ;;
            "Check Pod Details")
                check_pod_details "${namespace}" "${pod_name}"
                ;;
            "View Pod Logs")
                view_pod_logs "${namespace}" "${pod_name}"
                ;;
            "Check Liveness and Readiness Probes")
                check_liveness_readiness_probes "${namespace}" "${pod_name}"
                ;;
            "Check Ingress Configuration")
                check_ingress_configuration "${namespace}"
                ;;
            "Check Backend Connectivity")
                check_backend_connectivity "${namespace}" "${pod_name}" "${backend_url}"
                ;;
            "Monitor Pod After Applying Fixes")
                monitor_pod_after_applying_fixes "${namespace}"
                ;;
            "Quit" | q | Q | 8)
                echo -e "Exiting..."
                break
                ;;
            *)
                echo -e "Invalid option. Please try again."
                ;;
        esac
    done
}

diagnose_pod_issues() {
    if [[ "${1:-}" =~ ^(-h|--help|help|h)$ ]]; then
        echo -e "\nUsage: ${FUNCNAME[0]} <namespace> <pod_name>\n"
        echo -e "Description: Comprehensive diagnostic function that analyzes pod issues including"
        echo -e "             status, logs, events, configuration, connectivity, and network problems."
        echo -e "Arguments:"
        echo -e "  <namespace>   The namespace of the pod."
        echo -e "  <pod_name>    The name of the pod to diagnose.\n"
        return 0
    fi

    local namespace="${1:-}"
    local pod_name="${2:-}"

    if [[ -z "$namespace" ]]; then
        namespace=$(select_namespace) || return 1
        [[ -z "$namespace" ]] && echo "Namespace is empty. Exiting..." && return 1
        frame_message_1 "${GREEN}" "[✓] Selected Namespace: $namespace"
    fi

    if [[ -z "$pod_name" ]]; then
        pod_name=$(select_pod "$namespace") || return 1
        [[ -z "$pod_name" ]] && echo "Pod name is empty. Exiting..." && return 1
        frame_message_1 "${GREEN}" "[✓] Selected Pod: $pod_name"
    fi

    identify_affected_pod_and_namespace "$namespace" "$pod_name"
}

# OOMKilled detection
