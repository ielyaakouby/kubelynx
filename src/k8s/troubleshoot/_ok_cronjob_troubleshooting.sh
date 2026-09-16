#!/usr/bin/env bash
# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
#ActiveJobNmae="$(kubectl -n logging  describe cronjobs.batch  fluentd-cleanup | grep "Active Jobs:" | awk '{print $3}')"
#
#kubectl -n logging  describe jobs.batch "$(kubectl -n logging  describe cronjobs.batch  fluentd-cleanup | grep "Active Jobs:" | awk '{print $3}')"
#
#owner_details=$(kubectl get jobs "${owner}" -n "${namespace}" -o yaml 2>/dev/null)
#
#=================================================
#

describe_cronjob() {
    local namespace="$1"
    local cronJobName="$2"

    echo "Describing CronJob: $cronJobName"
    kubectl -n "$namespace" describe cronjob "$cronJobName" 2>/dev/null
}

# Function to describe a Job
describe_job() {
    local namespace="$1"
    local jobName="$2"

    echo "Describing Job: $jobName"
    kubectl -n "$namespace" describe job "$jobName" 2>/dev/null
}

format_datetime() {
    date -d "${1/Z/}" +"%d-%m-%Y at %H:%M:%S"
}

cronjob_troubleshooting_kget_pod_info() {
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
    pod_json=$(kubectl get pod "$pod_name" -n "$namespace" -o json 2>/dev/null)
    if [ -z "$pod_json" ]; then
        echo -e "${RED}⚠️ Pod not found in namespace ${namespace}.${RESET}"
        return 0
    fi

    if [[ -n "$pod_json" ]]; then
        pod_name=$(echo "$pod_json" | jq -r '.metadata.name')
        namespace=$(echo "$pod_json" | jq -r '.metadata.namespace')
        NODE_NAME=$(echo "$pod_json" | jq -r '.spec.nodeName // "N/A"')
        READY=$(echo "$pod_json" | jq -r '.status.containerStatuses | length as $total | map(select(.ready)) | length as $ready | "\($ready)/\($total)"')
        STATUS=$(echo "$pod_json" | jq -r '.status.phase')
        RESTARTS=$(echo "$pod_json" | jq -r '.status.containerStatuses | map(.restartCount) | add')
        pod_errors="$(kubectl -n $namespace logs $pod_name 2>/dev/null | grep -Ei "Error|Failed|ImagePullBackOff|CrashLoopBackOff|OOMKilled|Connection refused")"
        IFS='/' read -r readyCount totalCount <<<"$READY"
        if [[ "$readyCount" -ne "$totalCount" || "$STATUS" != "Running" ]]; then
            STATUS="            🔴 Pod is not fully ready or not running, and has restarts."
            status_msg_ko="            │Check for issues."
        else
            STATUS="            🟢 Pod is fully ready and running."
            status_msg_ok="            │ All systems go!"
        fi
        CONTAINER_STATUS=$(kubectl get pod "$pod_name" -n "$namespace" -o json 2>/dev/null \
            | jq -r '.status.containerStatuses[] |
        "Name: \(.name), State: \(.state | to_entries | map("\(.key): \(.value.reason // "running")") | join(", ")), Ready: \(.ready)"' \
            | sed 's/^/  /')
        RESTART_COUNT=$(echo "$pod_json" | jq -r '.status.containerStatuses[] | .restartCount' | awk '{sum+=$1} END {print sum}')
        IMAGE=$(echo "$pod_json" | jq -r '.spec.containers[] | "\(.name) -> image: \(.image)"')
        KIND=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null)
        LABELS=$(echo "$pod_json" | jq -r '.metadata.labels // {} | to_entries[] | "- \(.key): \(.value)"')
        CONTAINER_TOTAL=$(echo "$pod_json" | jq -r '.spec.containers[].name' | wc -l)
        CONTAINER_NAMES=$(echo "$pod_json" | jq -r '.spec.containers[].name' | tr '\n' ',' | sed 's/,$//')
        TOLERATIONS=$(echo "$pod_json" | jq -r '.spec.tolerations[]? | "- key: \(.key)\n  operator: \(.operator)\n  effect: \(.effect)"')
        NODE_SELECTOR=$(echo "$pod_json" | jq -r '.spec.nodeSelector // {} | to_entries[] | "- \(.key): \(.value)"')
        VOLUMES=$(echo "$pod_json" | jq -r '
        .spec.volumes[] |
        if .projected then
            "\(.name) -> (use secret: \(.projected.sources[]?.secret.name // "N/A") | pvc: N/A | use configMap: \(.projected.sources[]?.configMap.name // "N/A"))"
        elif .emptyDir then
            "\(.name) -> (emptyDir)"
        else
            "\(.name) -> (use secret: \(.secret.secretName // "N/A") | pvc: \(.persistentVolumeClaim.claimName // "N/A") | use configMap: \(.configMap.name // "N/A"))"
        end
        ')
        VOLUME_MOUNTS=$(echo "$pod_json" | jq -r '.spec.containers[].volumeMounts[] | "\(.name) -> (mounted at: \(.mountPath // "N/A") | subPath: \(.subPath // "N/A"))"')

        EVENTS=$(kubectl -n "$namespace" describe po "$pod_name" 2>/dev/null | awk '/Events:/,/^$/' 2>/dev/null)
    else
        echo "Error: Unable to retrieve pod information or pod does not exist."
    fi
    echo -e "\n${LIGHT_GREEN}${BOLD}            └││✨ Pod Information:${RESET}"
    echo -e "${LIGHT_RED}            └││ 📛 Name: $pod_name${RESET}"
    echo -e "${LIGHT_CYAN}            └││ 🌍 Namespace: $namespace${RESET}"
    echo -e "${YELLOW}            └││ 🖥️  Node Name: $NODE_NAME${RESET}"
    if [[ "$STATUS" == "            └││ 🔴 Pod is not fully ready or not running, and has restarts." ]]; then
        STATUS_COLOR=${LIGHT_RED}
        status_msg="$status_msg_ko"
    else
        STATUS_COLOR=${LIGHT_GREEN}
        status_msg="$status_msg_ok"
    fi
    echo -e "${STATUS_COLOR}            └││ 🟡 Status: $STATUS ($status_msg)${RESET}"
    echo -e "\n${LIGHT_RED}            └││🔄 Restart Count: $RESTART_COUNT${RESET}"
    echo -e "\n${LIGHT_CYAN}            └││ 🖼️  Image Used:${RESET}"
    if [[ -z "$IMAGE" ]]; then
        echo -e "${LIGHT_CYAN}          │├ None${RESET}"
    else
        echo "$IMAGE" | while read -r line; do
            printf "   ${LIGHT_CYAN} %s\n" "         │├ $line"
        done
    fi
    if [[ $KIND == "ReplicaSet" ]]; then
        KIND="deployment"
    fi
    echo -e "\n${LIGHT_GREEN}            └│ 🔖 Kind of Pod: $KIND${RESET}"
    echo -e "\n${LIGHT_YELLOW}            └│ 🧰 Containers:${RESET} "
    echo -e "   ${LIGHT_YELLOW}          │├ Total (${CONTAINER_TOTAL}): > $CONTAINER_NAMES"
    echo -e "\n${LIGHT_YELLOW}            └│ 🧩 Containers Status:${RESET}"
    if [[ -z "$CONTAINER_STATUS" ]]; then
        echo -e "   ${LIGHT_YELLOW}          │├ None${RESET}"
    else
        echo "$CONTAINER_STATUS" | while read -r line; do
            echo -e "${LIGHT_YELLOW}             │├ $line" #| column -t
        done
    fi
    echo -e "\n${LIGHT_BLUE}            └│ 🏷️ Labels:${RESET}"
    if [[ -z "$LABELS" ]]; then
        echo -e "   ${LIGHT_BLUE}          │├ None${RESET}"
    else
        echo "$LABELS" | while read -r line; do
            echo -e "   ${LIGHT_BLUE}          │├ $line"
        done
    fi
    echo -e "\n${ORANGE}            └│ 🔖 Tolerations:${RESET}"
    if [[ -z "$TOLERATIONS" ]]; then
        echo -e "   ${ORANGE}          │├ None${RESET}"
    else
        echo "$TOLERATIONS" | while read -r line; do
            echo -e "   ${ORANGE}          │├ $line"
        done
    fi
    echo -e "\n${LIGHT_YELLOW}            └│ 🔍 Node Selector:${RESET} "
    if [[ -z "$NODE_SELECTOR" ]]; then
        echo -e "   ${LIGHT_YELLOW}          │├ None${RESET}"
    else
        echo "$NODE_SELECTOR" | while read -r line; do
            echo -e "   ${LIGHT_YELLOW}          │├ $line"
        done
    fi
    echo -e "\n${LIGHT_GREEN}${BOLD}            └│ 📦 Volumes:${RESET}"
    if [[ -z "$VOLUMES" ]]; then
        echo -e "   ${LIGHT_GREEN}${BOLD}          │├ None${RESET}"
    else
        echo "$VOLUMES" | while read -r line; do
            echo -e "   ${LIGHT_GREEN}${BOLD}          │├ $line"
        done
    fi
    echo -e "\n${LIGHT_BLUE}${BOLD}            └│ 📂 Volume Mounts:${RESET}"
    if [[ -z "$VOLUME_MOUNTS" ]]; then
        echo -e "   ${LIGHT_BLUE}${BOLD}          │├ None${RESET}"
    else
        echo "$VOLUME_MOUNTS" | while read -r line; do
            echo -e "   ${LIGHT_BLUE}${BOLD}          │├ $line"
        done
    fi
}

get_cronjob_details() {
    local namespace="$1"
    local cronjob_name="$2"

    local COLOR_SOPHISTICATED="\e[1;34m" # Bright Blue (you can change this to any color you prefer)
    local COLOR_RESET="\e[0m"
    local cronjob_json=$(kubectl -n "$namespace" get cronjob "$cronjob_name" -o json 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        echo -e "${COLOR_SOPHISTICATED}Failed to retrieve CronJob details for $cronjob_name in namespace $namespace.${COLOR_RESET}"
        return 1
    fi

    local schedule=$(echo "$cronjob_json" | jq -r '.spec.schedule')
    local concurrency_policy=$(echo "$cronjob_json" | jq -r '.spec.concurrencyPolicy')
    local last_schedule_time=$(echo "$cronjob_json" | jq -r '.status.lastScheduleTime // "Never"')
    local last_successful_time=$(echo "$cronjob_json" | jq -r '.status.lastSuccessfulTime // "Never"')
    local service_account_name=$(echo "$cronjob_json" | jq -r '.spec.jobTemplate.spec.template.spec.serviceAccountName // "None"')
    local image=$(echo "$cronjob_json" | jq -r '.spec.jobTemplate.spec.template.spec.containers[0].image // "Not specified"')
    #local command=$(echo "$cronjob_json" | jq -r '.spec.jobTemplate.spec.template.spec.containers[0].command | @sh' | sed 's/\\n/return to new line/g' | tr -d "'") # Properly handle the new line
    local formatted_last_schedule_time=$(format_datetime "$last_schedule_time")
    local formatted_last_successful_time=$(format_datetime "$last_successful_time")
    local job_template_labels=$(echo "$cronjob_json" | jq -r '.spec.jobTemplate.spec.template.metadata.labels // "No labels" | to_entries | map("\(.key): \(.value)") | .[]')

    local creation_timestamp=$(echo "$cronjob_json" | jq -r '.metadata.creationTimestamp')

    echo -e "${COLOR_SOPHISTICATED}       CronJob Name: $cronjob_name${COLOR_RESET}"
    echo -e "${COLOR_SOPHISTICATED}       Namespace: $namespace${COLOR_RESET}"
    echo -e "${COLOR_SOPHISTICATED}       Schedule: $schedule${COLOR_RESET}"
    echo -e "${COLOR_SOPHISTICATED}       Concurrency Policy: $concurrency_policy${COLOR_RESET}"
    echo -e "${COLOR_SOPHISTICATED}       Last Scheduled Time: $formatted_last_schedule_time${COLOR_RESET}"
    echo -e "${COLOR_SOPHISTICATED}       Last Successful Time: $formatted_last_successful_time${COLOR_RESET}"

    echo -e "${COLOR_SOPHISTICATED}       Service Account Name: $service_account_name${COLOR_RESET}"
    echo -e "${COLOR_SOPHISTICATED}       Image: $image${COLOR_RESET}"

    if [[ -n "$job_template_labels" ]]; then
        echo -e "${COLOR_SOPHISTICATED}       Job Template Labels:${COLOR_RESET}"
        echo "$job_template_labels" | sed 's/^/         /' # Indent labels for better readability
    else
        echo -e "${COLOR_SOPHISTICATED}       Job Template Labels: No labels${COLOR_RESET}"
    fi

    echo -e "${COLOR_SOPHISTICATED}       Creation Timestamp: $creation_timestamp${COLOR_RESET}"
    #echo -e "${COLOR_SOPHISTICATED}Command:${COLOR_RESET}"
    #if [ -n "$command" ]; then
    #    echo "------"
    #    echo "$command" #| boxes -d stone -p a1
    #    echo "------"
    #else
    #    echo -e "${COLOR_SOPHISTICATED}Command: Not specified${COLOR_RESET}"
    #fi
}

get_associated_job_events_ok() {
    local namespace="$1"
    local job_name="$2"

    if [[ -z "$namespace" || -z "$job_name" ]]; then
        echo "Usage: get_associated_job_events <namespace> <job_name>"
        return 1
    fi

    # Get the Pods associated with the Job
    events=$(kubectl -n "$namespace" get events --field-selector involvedObject.kind=Job,involvedObject.name="$job_name" -o json 2>/dev/null)

    # Check if the output is not empty
    if [[ -z "$events" ]]; then
        echo "No events found for Job '$job_name' in namespace '$namespace'."
    else
        # Process each line of the output
        echo "$events" | jq -r '.items[] | .message' | while read -r line; do
            echo "Event: $line"
        done
    fi
}

get_associated_pods() {
    local namespace="$1"
    local job_name="$2"

    if [[ -z "$namespace" || -z "$job_name" ]]; then
        echo "Usage: get_associated_pods <namespace> <job_name>"
        return 1
    fi

    pods_failed="$(kubectl get pods -n "$namespace" --selector=job-name="$job_name" --no-headers | awk '$3 != "Running" && $3 != "Completed" {print $1}')"
    if [[ "$pods_failed" == "" ]]; then
        echo "         └│ No Pods found for Job '$job_name' in namespace '$namespace'."
    else
        printf "         └│ Pods associated with Job '%s' in namespace '%s':\n" "$job_name" "$namespace"
        for pod_name in $(echo "$pods_failed" | tr ' ' '\n'); do
            #echo -e "          ├ $pod_name"
            echo -e "\n            ═══════════════════ $pod_name ════════════"
            cronjob_troubleshooting_kget_pod_info $namespace $pod_name
            echo -e "\n            └│ Events for pod $pod_name"
            get_events_by_resource_type_and_resource_name "$namespace" "Pod" "$pod_name" | while read -r log; do
                echo "$log" | sed 's/^/             │/'
            done
        done
    fi
}

get_job_details() {
    local namespace=$1
    local job_name=$2

    job_details=$(kubectl -n "$namespace" get job "$job_name" -o json 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Error: Could not retrieve job details for $job_name in namespace $namespace${NC}"
        return 1
    fi

    local job_name=$(echo "$job_details" | jq -r '.metadata.name')
    local creation_timestamp=$(echo "$job_details" | jq -r '.metadata.creationTimestamp')
    local completion_time=$(echo "$job_details" | jq -r '.status.completionTime')
    local succeeded=$(echo "$job_details" | jq -r '.status.succeeded')
    local failed=$(echo "$job_details" | jq -r '.status.failed // "0"') # Default to "0" if null

    local owner_kind=$(echo "$job_details" | jq -r '.metadata.ownerReferences[0].kind // "N/A"')
    local owner_name=$(echo "$job_details" | jq -r '.metadata.ownerReferences[0].name // "N/A"')

    echo -e "${BLUE}       Job Name:${NC} $job_name"
    echo -e "${BLUE}       Namespace:${NC} $namespace"
    echo -e "${BLUE}       Creation Timestamp:${NC} $creation_timestamp"
    echo -e "${BLUE}       Completion Time:${NC} $completion_time"
    echo -e "${BLUE}       Succeeded:${NC} $succeeded"
    echo -e "${BLUE}       Failed:${NC} $failed"
    echo -e "${BLUE}       Owner Kind:${NC} $owner_kind"
    echo -e "${BLUE}       Owner Name:${NC} $owner_name"

    containers=$(echo "$job_details" | jq -r '.spec.template.spec.containers // empty')

    if [[ -z "$containers" || "$containers" == "null" ]]; then
        echo -e "${RED}No containers found for job $job_name.${NC}"
        return
    fi

    echo -e "${GREEN}       - Containers:${NC}"

    echo "$containers" | jq -c '.[]' 2>/dev/null | while IFS= read -r container; do
        if [[ -z "$container" || "$container" == "null" ]]; then
            echo -e "${RED}Error: Container data is null or empty.${NC}"
            continue
        fi
        local name=$(echo "$container" | jq -r '.name // "N/A"')
        local image=$(echo "$container" | jq -r '.image // "N/A"')
        #local command=$(echo "$container" | jq -r '.command | join(" ") // "N/A"')
        if echo "$container" | jq -e '.args' >/dev/null; then
            local args=$(echo "$container" | jq -r '.args | join(" ")')
        else
            local args=""
        fi
        echo -e "         ${GREEN}- Name:${NC} $name"
        echo -e "         ${GREEN}- Image used:${NC} $image"
        #echo -e "         ${GREEN}- Command:${NC}"
        #if [[ "$command" != "N/A" ]]; then
        #    echo "$command" | sed 's/^/              | /'
        #else
        #    echo -e "              | N/A"
        #fi
        if [[ -n "$args" ]]; then
            #echo -e "         ${GREEN}- Args:${NC}"
            #echo -e "              | \033[1;36m${args}\033[0m"
            GREEN="\033[0;32m"
            NC="\033[0m"

            if [[ -n "$args" ]]; then
                echo -e "         ${GREEN}- Args:${NC}"

                output=""
                IFS=' ' read -r -a arg_array <<<"$args"

                line=""
                for arg in "${arg_array[@]}"; do
                    if [[ ${#line} -gt 80 ]]; then
                        output+="              | \033[1;36m$line\033[0m\n"
                        line=""
                    fi
                    line+="$arg "
                done

                if [[ -n "$line" ]]; then
                    output+="              | \033[1;36m$line\033[0m\n"
                fi

                echo -e "$output"
            fi
        fi
    done
}

get_associated_job_name() {
    local namespace="$1"
    local job_template_labels="$(echo "$2" | sed 's/: /=/g')"
    local output_mode="$3"
    local color_success="\033[32m" # Green for success
    local color_warning="\033[33m" # Yellow for warnings
    local color_error="\033[31m"   # Red for errors
    local color_reset="\033[0m"    # Reset color
    local icon_info="ℹ️"
    local icon_warning="⚠️"
    local icon_error="❌"
    local icon_success="✅"

    if [[ "$output_mode" != "details" && "$output_mode" != "list_only" ]]; then
        echo -e "${color_error}$icon_error Invalid output mode. Use 'details' or 'list_only'.${color_reset}"
        return 1
    fi

    local failed_jobs_json=$(kubectl -n "logging" get jobs -l "app.kubernetes.io/name=fluentd-cleanup" -o json 2>/dev/null | jq -c '.items[] | select(.status.failed > 0 and (.status.conditions[]?.type == "Failed"))')

    local failed_jobs=$(echo $failed_jobs_json | jq -r '.metadata.name')

    if [[ -z "$failed_jobs" ]]; then
        echo -e "${color_warning}$icon_warning No jobs found with labels $job_template_labels in namespace $namespace.${color_reset}"
        return
    fi

    if [[ "$output_mode" == "details" ]]; then
        for job_name in $failed_jobs; do
            echo -e "${color_success}     ─────────────────────────────────────────────${color_reset}"
            echo -e "${color_success}      • Details for job: $job_name in namespace: $namespace${color_reset}"
            get_job_details "$namespace" "$job_name"

            echo -e "\n${color_info}      • Events for job: $job_name in namespace: $namespace${color_reset}"
            get_events_by_resource_type_and_resource_name "$namespace" "Job" "$job_name"

            echo -e "\n${color_info}      • Associated pods for job: \"$job_name\" in namespace: \"$namespace\"${color_reset}"
            get_associated_pods "$namespace" "$job_name"
        done
    else
        echo -e "${color_warning}    » Failed job list in namespace $namespace with labels $job_template_labels :${color_reset}"
        echo "$failed_jobs_json" | while read -r job; do
            name=$(echo "$job" | jq -r '.metadata.name')
            reason=$(echo "$job" | jq -r '.status.conditions[]? | select(.type == "Failed") | .reason // "N/A"')
            message=$(echo "$job" | jq -r '.status.conditions[]? | select(.type == "Failed") | .message // "N/A"')
            echo -e "${color_error}      » $icon_error $name${color_reset}"
            echo -e "${color_error}        » reason:  $reason${color_reset}"
            echo -e "${color_error}        » message: $message${color_reset}"
        done
    fi
}

# get_associated_job_name 'logging' "app.kubernetes.io/name=fluentd-cleanup" 'list_only'
# get_associated_job_name 'logging' "app.kubernetes.io/name=fluentd-cleanup" 'details'

kget_cronjob_details2() {
    local namespace="$1"
    local cronjob_name="$2"

    if [[ -z "$namespace" ]]; then
        namespace=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | fzf --prompt="Select a namespace: ")
        if [[ -z "$namespace" ]]; then
            echo "No namespace selected, exiting."
            return 1
        fi
    fi
    if [[ -z "$cronjob_name" ]]; then
        cronjob_name=$(kubectl get cronjob -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | fzf --prompt="Select a CronJob in namespace '$namespace': ")
        if [[ -z "$cronjob_name" ]]; then
            echo "No CronJob selected, exiting."
            return 1
        fi
    fi

    # step 1 get_cronjob_details
    echo "   ¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤"
    echo "   [step 1] CronJob details of \"$cronjob_name\""
    echo "   ¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤"
    get_cronjob_details $namespace $cronjob_name

    echo "   ¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤"
    echo "   [step 2] CronJob Event of \"$cronjob_name\""
    echo "   ¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤"
    get_events_by_resource_type_and_resource_name "$namespace" "CronJob" "$cronjob_name"
    # step 2 get get_associated_job_name

    local cronjob_json=$(kubectl -n "$namespace" get cronjob "$cronjob_name" -o json 2>/dev/null)
    local job_template_labels=$(echo "$cronjob_json" | jq -r '.spec.jobTemplate.spec.template.metadata.labels // "No labels" | to_entries | map("\(.key): \(.value)") | .[]')
    local cronjob_job_template_name="$(echo $job_template_labels | awk '{print $2}')"

    echo "   ¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤"
    echo "   [step 3] Jobs associated to CronJob (status) $cronjob_name"
    echo "   ¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤"
    get_associated_job_name $namespace "$job_template_labels" "list_only"
    echo "   ¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤"
    echo "   ¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤"
    echo "   [step 4] Jobs associated to CronJob (details) $cronjob_name"
    echo "   ¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤"
    # step 3 get_job_details -get_associated_job_details
    get_associated_job_name $namespace "$job_template_labels" "details"

}

kget_cronjob_details() {
    local arg1="$1"
    local arg2="$2"
    if [[ "$1" =~ ^( -h|--help|help|h)$ ]]; then
        echo -e "usage : \n kget_cronjob_details job [job_name]\n kget_cronjob_details [namespace] [cronjob_name]"
        return
    fi
    if [[ $arg1 == "job" ]]; then
        if [[ $arg1 == "help" ]]; then
            echo "usage : $0 job [job_name]"
            exit 0
        else
            job_name="$arg2"
            namespace=$(kubectl get job --all-namespaces -o custom-columns=":metadata.namespace,:metadata.name" | grep " $job_name$" | awk '{print $1}')
            if [ -z "$namespace" ]; then
                echo "Job '$job_name' not found across any namespace."
                exit 0
            fi
        fi

        kind_name="$(kubectl -n $namespace get jobs.batch $job_name -o json | jq -r '.metadata.ownerReferences[].name')"
        if [[ $kind_name == "CronJob" ]]; then
            cronjob_name="$kind_name"
            kget_cronjob_details2 $namespace $cronjob_name
        else
            echo -e "   the owner is not a cronjob\n"
            #exit 0

            echo "   ¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤"
            echo "   [step 1] get job details $namespace $job_name  "
            echo "   ¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤"
            get_job_details $namespace $job_name
            echo "   ¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤"
            echo "   [step 2] get associated pods : $namespace $job_name  "
            echo "   ¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤¤"
            get_associated_pods $namespace $job_name
        fi
        # logging_name="$(kubectl -n $namespace get jobs.batch $job_name -o json | jq -r '.metadata.ownerReferences[].name')"
    else
        local namespace="$1"
        local cronjob_name="$2"
        if [[ -z "$namespace" ]]; then
            namespace=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | fzf --prompt="Select a namespace: ")
            if [[ -z "$namespace" ]]; then
                echo "No namespace selected, exiting."
                return 1
            fi
        fi
        if [[ -z "$cronjob_name" ]]; then
            cronjob_name=$(kubectl get cronjob -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | fzf --prompt="Select a CronJob in namespace '$namespace': ")
            if [[ -z "$cronjob_name" ]]; then
                echo "No CronJob selected, exiting."
                return 1
            fi
        fi
        kget_cronjob_details2 $namespace $cronjob_name
    fi

}
