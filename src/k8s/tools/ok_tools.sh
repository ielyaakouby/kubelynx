#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
pad_line() {
    local padding_char="─" #°
    local prompt_length=${#1}
    local terminal_width=$(tput cols)
    local fill_width=$((terminal_width - prompt_length))
    printf -v pad_line '%*s' "$fill_width" '' # create a space-filled line
    pad_line=${pad_line// /$padding_char}     # replace spaces with '═'
    echo -n "$pad_line"
}

kget_pods_by_status() {
    local status_descriptions=(
        "ContainerCreating:        Pod is being created and is not yet running."
        "ContainerStatusUnknown:   The container's status cannot be determined."
        "CrashLoopBackOff:         Pod is crashing repeatedly, Kubernetes is backing off from restarting it."
        "Error:                    The pod has encountered an error during its execution."
        "ImagePullBackOff:         Kubernetes is unable to pull the container image."
        "Init:CrashLoopBackOff:    Init container is crashing repeatedly."
        "OOMKilled:                The pod was killed because it exceeded the memory limits."
        "OutOfcpu:                 The pod has been throttled due to CPU resource limits."
        "OutOfmemory:              The pod has been throttled due to memory resource limits."
        "Pending:                  Pod is waiting for resources to be allocated (e.g., scheduling issues)."
        "Terminating:              Pod is in the process of being terminated."
        "NodeLost:                 The node hosting the pod is unreachable."
        "Unknown:                  The status of the pod cannot be determined."
        "Evicted:                  Pod was evicted from the node due to resource constraints."
        "PodInitializing:          The pod is in the initialization phase."
        "Completed:                The pod has completed its execution (may indicate issues for long-running pods)."
        "DeadlineExceeded:         The job exceeded its time limit."
        "ImageInspectError:        An error occurred while inspecting the image."
        "ContainerCannotRun:       The container failed to start due to configuration issues."
        "ErrImagePull:             An error occurred while pulling the container image."
        "CreateContainerConfigError: There was a configuration error creating the container."
        "InvalidImageName:         The specified image name is invalid."
        "Shutdown:                 The pod is in the process of shutting down."
        "Failed:                   The pod has failed to run."
        "Not Running:              Pods that are not in a 'Running' state and have containers not ready."
    )

    if [[ "$1" =~ ^( -h|--help|help|h)$ ]]; then
        echo -e "\nKubernetes Pod Statuses:\n"
        for desc in "${status_descriptions[@]}"; do
            echo "$desc"
        done
        echo -e "\nUsage:               Run the script and select a status to check for pods in that state."
        return
    fi

    local status_list=(
        "ContainerCreating"
        "ContainerStatusUnknown"
        "CrashLoopBackOff"
        "Error"
        "ImagePullBackOff"
        "Init:CrashLoopBackOff"
        "OOMKilled"
        "OutOfcpu"
        "OutOfmemory"
        "Pending"
        "Terminating"
        "NodeLost"
        "Unknown"
        "Evicted"
        "PodInitializing"
        "Completed"
        "DeadlineExceeded"
        "ImageInspectError"
        "ContainerCannotRun"
        "ErrImagePull"
        "CreateContainerConfigError"
        "InvalidImageName"
        "Shutdown"
        "Failed"
        "Not Running"
        "Running"
        "all"
    )

    local status_list_2=(
        "ContainerCreating"
        "ContainerStatusUnknown"
        "CrashLoopBackOff"
        "Error"
        "ImagePullBackOff"
        "Init:CrashLoopBackOff"
        "OOMKilled"
        "OutOfcpu"
        "OutOfmemory"
        "Pending"
        "Terminating"
        "NodeLost"
        "Unknown"
        "Evicted"
        "PodInitializing"
        "Completed"
        "DeadlineExceeded"
        "ImageInspectError"
        "ContainerCannotRun"
        "ErrImagePull"
        "CreateContainerConfigError"
        "InvalidImageName"
        "Shutdown"
        "Failed"
    )

    namespace="$1"
    selected_status="$2"

    if [[ -z "$selected_status" ]]; then
        selected_status=$(printf "%s\n" "${status_list[@]}" | fzf --header="Select a status to filter by (or 'all' for all statuses):")
    fi

    if [[ -z "$namespace" ]]; then
        namespace=""
        #namespace=$(select_namespace) || exit 1
        namespaces=$(kubectl get namespaces --no-headers -o custom-columns=":metadata.name" 2>/dev/null)
        selected_namespace=$(echo -e "all\n$namespaces" | fzf --prompt "📦 Select a namespace: ")
    else
        selected_namespace="$namespace"
    fi

    if [[ "$selected_namespace" == "all" ]]; then
        namespace="--all-namespaces"
    else
        namespace="$selected_namespace"
    fi

    #echo -e "${COLOR_ORANGE}Selected status:${COLOR_RESET} $selected_status  ${COLOR_ORANGE}Namespace:${COLOR_RESET} $namespace"
    namespace_in_case_all="$(echo "--all-namespaces" | sed 's/--\([a-zA-Z]*\)-.*/\1/')"
    echo -e "${COLOR_ORANGE}k8s check ${COLOR_RESET} $selected_status ${COLOR_ORANGE} in ${COLOR_RESET} $namespace_in_case_all ${COLOR_ORANGE}namespace(s)${COLOR_RESET}"
    all_pod_not_running_data=""
    all_pod_running_data=""
    all_pod_not_running_data_namespaces=""
    all_pod_running_data_namespaces=""
    selected_statuses=""
    #all_pod_not_running_data_table=""

    if [[ "$namespace" == "--all-namespaces" ]]; then
        #all_pod_not_running_data="$(kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name} {.status.phase} {.status.containerStatuses[*].ready}{"\n"}{end}' | awk '($3 != "Succeeded" || $3 != "Running || $3 != "Completed") && ($4 == "false")')"

        all_pod_not_running_data="$(kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name} {.status.phase} {.status.containerStatuses[*].ready}{"\n"}{end}' | awk '($3 != "Succeeded" && $3 != "Running" && $3 != "Completed") && ($4 == "false")')"

        all_pod_running_data="$(kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name} {.status.phase} {.status.containerStatuses[*].ready}{"\n"}{end}' | awk '($3 == "Succeeded" || $3 == "Running") && ($4 == "true")')"
    else
        all_pod_not_running_data="$(kubectl get pods -n "$namespace" -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name} {.status.phase} {.status.containerStatuses[*].ready} {.status.containerStatuses[*].state.terminated.reason}{"\n"}{end}' | awk '($3 != "Succeeded" || $3 != "Running") && ($4 == "false" && $5 != "Completed")')"

        all_pod_running_data="$(kubectl get pods -n "$namespace" -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name} {.status.phase} {.status.containerStatuses[*].ready}{"\n"}{end}' | awk '($3 == "Succeeded" || $3 == "Running") && ($4 == "true")')"
    fi

    all_pod_not_running_data_namespaces=$(echo "$all_pod_not_running_data" | awk '{print $1}' | sort -u)
    #all_pod_running_data_namespaces=$(echo "$all_pod_running_data" | awk '{print $1}' | sort -u)

    # ►
    if [[ "$selected_status" == "Not Running" ]]; then
        echo "$all_pod_not_running_data_namespaces" | while read namespace; do
            echo -e "\n──┬ namespace: $namespace"
            echo "$all_pod_not_running_data" | grep "$namespace" | awk '{print $1, $2}' | while read -r ns pod; do
                #result_pod_event=$(kubectl -n "$ns" get events --field-selector involvedObject.kind="Pod",involvedObject.name="$pod" -o json 2>/dev/null | jq -r '.items[] | select(.type != "Normal" or (.reason | test("Unhealthy|BackOff|Error|Failed|CrashLoopBackOff|Warning"))) | "[" + .reason + "] " + (.message | split(" ")[0:10] | join(" "))')
                result_pod_event=$(kubectl -n "$ns" get events --field-selector involvedObject.kind="Pod",involvedObject.name="$pod" -o json 2>/dev/null | jq -r '
                    .items[]
                    | select(.type != "Normal" or (
                        .reason | test("CrashLoopBackOff|Warning|NodeNotReady|PodEvicted|OOMKilled|OutOfcpu|OutOfmemory|Pending|Terminating|NodeLost|Unknown|Evicted|DeadlineExceeded|ImageInspectError|ContainerCannotRun|ErrImagePull|CreateContainerConfigError|InvalidImageName|Shutdown|Failed|Unhealthy|BackOff|Error")
                    ))
                    | "[" + .reason + "] " + (.message | split(" ")[0:10] | join(" "))
                ')

                ## result_pod_logs0=$(kubectl logs "$pod" -n "$ns" 2>/dev/null)
                result_pod_logs=$(kubectl logs "$pod" -n "$ns" 2>/dev/null | grep -iE "Unhealthy|Error|Failed|ImagePullBackOff|CrashLoopBackOff|OOMKilled|Connection refused")
                #if [[ -z "${result_pod_event}" || -z "${result_pod_event}" ]]; then
                if [[ ${result_pod_event} != "" || ${result_pod_logs} != "" ]]; then
                    #echo "──┬ namespace: $namespace"
                    #echo "  │"
                    echo "  ├─ ${pod}"
                    #echo "  ├─┬[pod] ${pod}"
                    #echo "  │ ┼┬"
                    #if [[ ${result_pod_logs} != "" ]]; then
                    #    echo "${result_pod_logs}" | while read log; do
                    #        echo -e "  │  ├ ${ORANGE}[log]$log${RESET}"
                    #    done
                    #fi
                    #if [[ ${result_pod_event} != "" ]]; then
                    #    echo "${result_pod_event}" | while read event; do
                    #        echo -e "  │  ├ ${ORANGE}[event]$event${RESET}"
                    #    done
                    #fi

                    #if [[ ${result_pod_event} == "" || ${result_pod_event} == "" ]]; then
                    #    echo -e "  │  ├ no event / log error"
                    #fi
                fi

            done
        done
        # elif [[ "$selected_status" == "Running" ]]; then

    elif [[ "$selected_status" == "all" ]]; then
        selected_statuses=("${status_list[@]:0:${#status_list[@]}-2}")
        for status in "${selected_statuses[@]}"; do

            if echo "$all_pod_not_running_data_namespaces" | grep -q "$status"; then
                echo -e "\n${COLOR_ORANGE}Status:${COLOR_RESET} $status"
            fi
            if [[ "$namespace" == "--all-namespaces" ]]; then
                echo "$all_pod_not_running_data_namespaces" | while read -r namespace; do
                    sma="$(kubectl get po -n "$namespace" --no-headers | grep -v "Running\|Completed" | awk -v status="$status" '$3 == status {print $1, $2, $3, $4}')"
                    if [[ -n "$sma" ]]; then
                        # Display namespace header
                        echo -e "\n${ORANGE}──┬ ${RESET}${ORANGE} namespace: $namespace${RESET}"
                        # Iterate through each pod in the namespace
                        echo "$sma" | awk '{print $1}' | while read -r pod; do
                            # Get and filter pod-related events
                            #result_pod_event=$(kubectl -n "$namespace" get events --field-selector involvedObject.kind="Pod",involvedObject.name="$pod" -o json 2>/dev/null | \
                            #    jq -r '.items[] | select(.type != "Normal" or (.reason | test("BackOff|Error|Failed|ImagePullBackOff|CrashLoopBackOff|Warning"))) | "[" + .reason + "] " + (.message | split(" ")[0:10] | join(" "))')
                            result_pod_event=$(kubectl -n "$ns" get events --field-selector involvedObject.kind="Pod",involvedObject.name="$pod" -o json 2>/dev/null | jq -r '
                                .items[]
                                | select(.type != "Normal" or (
                                    .reason | test("CrashLoopBackOff|Warning|NodeNotReady|PodEvicted|OOMKilled|OutOfcpu|OutOfmemory|Pending|Terminating|NodeLost|Unknown|Evicted|DeadlineExceeded|ImageInspectError|ContainerCannotRun|ErrImagePull|CreateContainerConfigError|InvalidImageName|Shutdown|Failed|Unhealthy|BackOff|Error")
                                ))
                                | "[" + .reason + "] " + (.message | split(" ")[0:10] | join(" "))
                            ')

                            # Display pod header
                            echo "  │"
                            echo "  ├─┬[pod] ${pod}"
                            echo "  │ ┼┬"
                            # Print each event under the pod header
                            echo "$result_pod_event" | while read -r event; do
                                echo -e "${ORANGE}  │ ├ ${RESET}${COLOR_LIGHT_RED}[event]$event${RESET}"
                            done
                        done
                    fi
                done
            else
                # For a specific namespace (not all namespaces)
                sma=$(kubectl get po -n "$namespace" --no-headers | grep -v "Running\|Completed" | awk -v status="$status" '$3 == status {print $1, $2, $3, $4}')
                if [[ -n "$sma" ]]; then
                    # Display namespace header
                    echo -e "\n${ORANGE}──┬ ${RESET}${ORANGE} namespace: $namespace${RESET}"
                    # Iterate through each pod in the namespace
                    echo "$sma" | awk '{print $1}' | while read -r pod; do
                        #result_pod_event=$(kubectl -n "$namespace" get events --field-selector involvedObject.kind="Pod",involvedObject.name="$pod" -o json 2>/dev/null | \
                        #    jq -r '.items[] | select(.type != "Normal" or (.reason | test("BackOff|Error|Failed|CrashLoopBackOff|Warning"))) | "[" + .reason + "] " + (.message | split(" ")[0:10] | join(" "))')
                        result_pod_event=$(kubectl -n "$namespace" get events --field-selector involvedObject.kind="Pod",involvedObject.name="$pod" -o json 2>/dev/null \
                            | jq -r '.items[]
                                | select(.type != "Normal" or (
                                    .reason | test("CrashLoopBackOff|Warning|NodeNotReady|PodEvicted|OOMKilled|OutOfcpu|OutOfmemory|Pending|Terminating|NodeLost|Unknown|Evicted|DeadlineExceeded|ImageInspectError|ContainerCannotRun|ErrImagePull|CreateContainerConfigError|InvalidImageName|Shutdown|Failed|Unhealthy|BackOff|Error")
                                ))
                                | "[" + .reason + "] " + (.message | split(" ")[0:10] | join(" "))
                        ')

                        #result_pod_logs=$(kubectl logs "$pod" -n "$namespace" 2>/dev/null | grep -iE "Unhealthy|Error|Failed|ImagePullBackOff|CrashLoopBackOff|OOMKilled|Connection refused")
                        result_pod_logs=$(kubectl logs "$pod" -n "$namespace" 2>/dev/null | grep -iE "Unhealthy|Error|Failed|ImagePullBackOff|CrashLoopBackOff|OOMKilled|Connection refused|NodeNotReady|PodEvicted|OutOfcpu|OutOfmemory|Pending|Terminating|NodeLost|Unknown|Evicted|DeadlineExceeded|ImageInspectError|ContainerCannotRun|ErrImagePull|CreateContainerConfigError|InvalidImageName|Shutdown")

                        if [[ ${result_pod_event} != "" || ${result_pod_logs} != "" ]]; then
                            echo "  │"
                            echo "  ├─┬[pod] ${pod}"
                            echo "  │ ┼┬"
                            if [[ ${result_pod_logs} != "" ]]; then
                                echo "${result_pod_logs}" | while read log; do
                                    echo -e "  │  ├ ${ORANGE}[log]$log${RESET}"
                                done
                            fi
                            if [[ ${result_pod_event} != "" ]]; then
                                echo "${result_pod_event}" | while read event; do
                                    echo -e "  │  ├ ${ORANGE}[event]$event${RESET}"
                                done
                            fi
                            if [[ ${result_pod_event} == "" || ${result_pod_event} == "" ]]; then
                                echo -e "  │  ├ no event / log error"
                            fi
                        fi
                    done
                fi
            fi
        done
    else
        status=("$selected_status")
        if [[ "$namespace" == "--all-namespaces" ]]; then
            echo "$all_pod_not_running_data_namespaces" | while read -r namespace; do
                sma=$(kubectl get po -n "$namespace" --no-headers | grep -v "Running\|Completed" | awk -v status="$selected_status" '$3 == status {print $1, $2, $3, $4}')
                if [[ -n "$sma" ]]; then
                    # Display namespace header
                    echo -e "\n${ORANGE}──┬ ${RESET}${ORANGE} namespace: $namespace${RESET}"

                    # Iterate through each pod in the namespace
                    echo "$sma" | awk '{print $1}' | while read -r pod; do
                        # Get and filter pod-related events
                        result_pod_event=$(kubectl -n "$namespace" get events --field-selector involvedObject.kind="Pod",involvedObject.name="$pod" -o json 2>/dev/null \
                            | jq -r '.items[] | select(.type != "Normal" or (.reason | test("BackOff|Error|Failed|CrashLoopBackOff|Warning"))) | "[" + .reason + "] " + (.message | split(" ")[0:10] | join(" "))')
                        #  result_pod_logs0=$(kubectl logs "$pod" -n "$namespace" 2>/dev/null)
                        result_pod_logs=$(kubectl logs "$pod" -n "$namespace" 2>/dev/null | grep -iE "Unhealthy|Error|Failed|ImagePullBackOff|CrashLoopBackOff|OOMKilled|Connection refused")
                        if [[ ${result_pod_event} != "" || ${result_pod_logs} != "" ]]; then
                            echo "  │"
                            echo "  ├─┬[pod] ${pod}"
                            echo "  │ ┼┬"
                            if [[ ${result_pod_logs} != "" ]]; then
                                echo "${result_pod_logs}" | while read log; do
                                    echo -e "  │  ├ ${ORANGE}[log]$log${RESET}"
                                done
                            fi
                            if [[ ${result_pod_event} != "" ]]; then
                                echo "${result_pod_event}" | while read event; do
                                    echo -e "  │  ├ ${ORANGE}[event]$event${RESET}"
                                done
                            fi
                            if [[ ${result_pod_event} == "" || ${result_pod_event} == "" ]]; then
                                echo -e "  │  ├ no event / log error"
                            fi
                        fi
                    done
                fi
            done
        else
            # Get pods that are not in Running or Completed state
            sma=$(kubectl get po -n "$namespace" --no-headers | grep -v "Running\|Completed" | awk -v status="$selected_status" '$3 == status {print $1, $2, $3, $4}')
            if [[ -n "$sma" ]]; then
                # Print namespace header with no trailing spaces
                echo -e "\n${ORANGE}──┬ ${RESET}${ORANGE} namespace: $namespace${RESET}"

                echo "$sma" | awk '{print $1}' | while read -r pod; do
                    result_pod_event=$(kubectl -n "$namespace" get events --field-selector involvedObject.kind="Pod",involvedObject.name="$pod" -o json 2>/dev/null \
                        | jq -r '.items[] | select(.type != "Normal" or (.reason | test("BackOff|Error|Failed|CrashLoopBackOff|Warning"))) | "[" + .reason + "] " + (.message | split(" ")[0:10] | join(" "))')
                    result_pod_logs=$(kubectl logs "$pod" -n "$namespace" 2>/dev/null | grep -iE "Unhealthy|Error|Failed|ImagePullBackOff|CrashLoopBackOff|OOMKilled|Connection refused")
                    if [[ ${result_pod_event} == "" || ${result_pod_logs} == "" ]]; then
                        echo "  │"
                        echo "  ├─┬[pod] ${pod}"
                        echo "  │ ┼┬"
                        if [[ ${result_pod_logs} != "" ]]; then
                            echo "${result_pod_logs}" | while read log; do
                                echo -e "  │  ├ ${ORANGE}[log]$log${RESET}"
                            done
                        fi
                        if [[ ${result_pod_event} != "" ]]; then
                            echo "${result_pod_event}" | while read event; do
                                echo -e "  │  ├ ${ORANGE}[event]$event${RESET}"
                            done
                        fi
                        if [[ ${result_pod_event} == "" || ${result_pod_logs} == "" ]]; then
                            echo -e "  │  ├ no event / log error"
                        fi
                    fi
                done
            fi
        fi
    fi
}

ok_get_service_info() {
    local selected_namespace="$1"
    local selected_service="$2"

    if [[ -z "$selected_namespace" ]]; then
        local namespaces
        namespaces=$(kubectl get namespaces --no-headers -o custom-columns=":metadata.name" 2>/dev/null)

        if [[ -z "$namespaces" ]]; then
            frame_message "\033[0;31m" "❌ No namespaces found."
            return 1
        fi

        selected_namespace=$(echo "$namespaces" | fzf --prompt "🌐 Select a namespace: ")
        if [[ -z "$selected_namespace" ]]; then
            frame_message "\033[0;31m" "❌ No namespace selected."
            return 1
        fi
    fi

    if [[ -z "$selected_service" ]]; then
        local services
        services=$(kubectl get svc -n "$selected_namespace" --no-headers -o custom-columns=":metadata.name" 2>/dev/null)

        if [[ -z "$services" ]]; then
            frame_message "\033[0;31m" "❌ No services found in namespace '$selected_namespace'."
            return 1
        fi

        selected_service=$(echo "$services" | fzf --prompt "📦 Select a service in namespace '$selected_namespace': ")
        if [[ -z "$selected_service" ]]; then
            frame_message "\033[0;31m" "❌ No service selected."
            return 1
        fi
    fi

    service_info=$(kubectl get service "$selected_service" -n "$selected_namespace" -o json 2>/dev/null)
    if [[ -z "$service_info" ]]; then
        frame_message "\033[0;31m" "❌ Service '$selected_service' not found in namespace '$selected_namespace'."
        return 1
    fi

    service_type=$(echo "$service_info" | jq -r '.spec.type')
    case "$service_type" in
        ClusterIP)
            cluster_ip=$(echo "$service_info" | jq -r '.spec.clusterIP')
            service_url="http://$cluster_ip"
            ;;
        NodePort)
            node_port=$(echo "$service_info" | jq -r '.spec.ports[0].nodePort')
            service_url="http://<node-ip>:$node_port"
            ;;
        LoadBalancer)
            load_balancer_ip=$(echo "$service_info" | jq -r '.status.loadBalancer.ingress[0].ip')
            if [[ -z "$load_balancer_ip" ]]; then
                frame_message "\033[0;31m" "❌ LoadBalancer service is still pending an external IP."
                return 1
            fi
            service_url="http://$load_balancer_ip"
            ;;
        *)
            frame_message "\033[0;31m" "❌ Service type '$service_type' is not supported."
            return 1
            ;;
    esac

    service_fqdn="$selected_service.$selected_namespace.svc.cluster.local"
    pods_attached=$(kubectl get pods -n "$selected_namespace" --selector $(kubectl get service "$selected_service" -n "$selected_namespace" -o jsonpath='{.spec.selector}' 2>/dev/null | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")') 2>/dev/null)

    SERVICE_PORTS_JSON=$(kubectl get svc -n "$selected_namespace" "$selected_service" -o=json 2>/dev/null | jq '{
        Ports: [.spec.ports[].port],
        TargetPorts: [.spec.ports[].targetPort]
    }')

    echo -e "\n🎉 Selected Information:\n"
    echo -e "🔹 Namespace: \033[0;32m$selected_namespace\033[0m"
    echo -e "🔹 Service: \033[0;32m$selected_service\033[0m"
    echo -e "🔹 Service Type: \033[0;34m$service_type\033[0m"
    echo -e "🔹 Service URL: \033[0;34m$service_url\033[0m"
    echo -e "🔹 Service FQDN: \033[0;34m$service_fqdn\033[0m\n"
    echo -e "🔹 Attached to Pods:"
    echo "$pods_attached" | while read -r line; do
        echo -e "  🔹 $line"
    done
    echo -e "\n🔹 Ports:"
    echo "$SERVICE_PORTS_JSON" | jq -r '.Ports[]' | while read -r port; do
        echo -e "  🔹 Port: $port"
    done
    echo "$SERVICE_PORTS_JSON" | jq -r '.TargetPorts[]' | while read -r targetPort; do
        echo -e "  🔹 Target Port: $targetPort"
    done
}

parse_arguments() {
    if [[ "$#" -eq 5 && "$2" == "where" && "$3" == "label" && ("$4" == "is" || "$4" == "in") ]]; then
        RESOURCE="$1"
        LABELS="${5//,/\\|}" # Replace commas with '|' for regex
    else
        echo "Missing or incorrect arguments. Entering interactive mode."

        echo "Please select a resource kind from the following options:"
        RESOURCE=$(list_available_resources | fzf --prompt="Select resource type: ")

        if [[ -z $RESOURCE ]]; then
            echo "No resource selected. Exiting."
            exit 1
        fi

        echo "Please specify at least one label or multiple labels separated by commas."
        read -p "Enter labels (app=name <> app=name or env=prd <> app=name and env=prd...) : " input_labels

        if [[ $input_labels == *"or"* ]]; then
            LABELS=$(echo "$input_labels" | sed 's/ \(or\) /\|/g') # app.kubernetes.io/name=yesterday|app.kubernetes.io/component=monit|ing
            echo "LABELS or = $LABELS"
        elif [[ $input_labels == *"and"* ]]; then
            LABELS=$(echo "$input_labels" | sed 's/ *and */,/g')
            echo "LABELS and = $LABELS"
        else
            LABELS="$input_labels"
        fi
        #LABELS="${input_labels//,/\\|}"  # Replace commas with '|' for regex
    fi
}

list_available_resources() {
    kubectl api-resources --verbs=list --no-headers | awk '{print $1}' 2>/dev/null
}

display_resources_with_labels() {
    echo -e "${COLOR_BAGROUND_GREEN}NAMESPACE\tPOD\tSTATUS\tREADY\tAGE${reset}"

    kubectl get "$RESOURCE" --all-namespaces --show-labels 2>/dev/null \
        | grep -E "$LABELS" \
        | awk -v colors="${colors[*]}" -v reset="$reset" '
    BEGIN {
        split(colors, colorArray, " ");
        colorIndex = 0;
    }
    {
        namespace = $1;  # Assuming namespace is the first column
        if (!(namespace in colorMap)) {
            colorMap[namespace] = colorArray[++colorIndex % length(colorArray)];
        }
        printf "%s%s\t%s\t%s\t%s\t%s%s\n", colorMap[namespace], $1, $2, $3, $4, $6, reset;
    }' | column -t
}

ok_display_resources_with_labels() {
    parse_arguments "$@"
    define_colors
    display_resources_with_labels
}
