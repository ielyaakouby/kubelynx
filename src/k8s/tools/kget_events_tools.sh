#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
display_cronjob_details() {
    local namespace="$1"
    local cronjob_name="$2"

    local COLOR_SOPHISTICATED="\e[1;34m" # Bright Blue (you can change this to any color you prefer)
    local COLOR_RESET="\e[0m"
    local cronjob_json=$(kubectl -n "$namespace" get cronjob "$cronjob_name" -o json)

    if [[ $? -ne 0 ]]; then
        echo -e "${COLOR_SOPHISTICATED}Failed to retrieve CronJob details for $cronjob_name in namespace $namespace.${COLOR_RESET}"
        return 1
    fi

    local schedule
    local concurrency_policy
    local last_schedule_time
    local last_successful_time
    local service_account_name
    local image
    local command
    local job_template_labels
    local creation_timestamp

    schedule=$(echo "$cronjob_json" | jq -r '.spec.schedule')
    concurrency_policy=$(echo "$cronjob_json" | jq -r '.spec.concurrencyPolicy')
    last_schedule_time=$(echo "$cronjob_json" | jq -r '.status.lastScheduleTime // "Never"')
    last_successful_time=$(echo "$cronjob_json" | jq -r '.status.lastSuccessfulTime // "Never"')
    service_account_name=$(echo "$cronjob_json" | jq -r '.spec.jobTemplate.spec.template.spec.serviceAccountName // "None"')
    image=$(echo "$cronjob_json" | jq -r '.spec.jobTemplate.spec.template.spec.containers[0].image // "Not specified"')
    command=$(echo "$cronjob_json" | jq -r '.spec.jobTemplate.spec.template.spec.containers[0].command | @sh' | sed 's/\\n/return to new line/g' | tr -d "'") # Properly handle the new line

    job_template_labels=$(echo "$cronjob_json" | jq -r '.spec.jobTemplate.spec.template.metadata.labels // "No labels" | to_entries | map("\(.key): \(.value)") | .[]')

    creation_timestamp=$(echo "$cronjob_json" | jq -r '.metadata.creationTimestamp')

    echo -e "${COLOR_SOPHISTICATED}CronJob Name: $cronjob_name${COLOR_RESET}"
    echo -e "${COLOR_SOPHISTICATED}Namespace: $namespace${COLOR_RESET}"
    echo -e "${COLOR_SOPHISTICATED}Schedule: $schedule${COLOR_RESET}"
    echo -e "${COLOR_SOPHISTICATED}Concurrency Policy: $concurrency_policy${COLOR_RESET}"
    echo -e "${COLOR_SOPHISTICATED}Last Scheduled Time: $last_schedule_time${COLOR_RESET}"
    echo -e "${COLOR_SOPHISTICATED}Last Successful Time: $last_successful_time${COLOR_RESET}"
    echo -e "${COLOR_SOPHISTICATED}Service Account Name: $service_account_name${COLOR_RESET}"
    echo -e "${COLOR_SOPHISTICATED}Image: $image${COLOR_RESET}"

    if [[ -n "$job_template_labels" ]]; then
        echo -e "${COLOR_SOPHISTICATED}Job Template Labels:${COLOR_RESET}"
        echo "$job_template_labels" | sed 's/^/  /' # Indent labels for better readability
    else
        echo -e "${COLOR_SOPHISTICATED}Job Template Labels: No labels${COLOR_RESET}"
    fi

    echo -e "${COLOR_SOPHISTICATED}Creation Timestamp: $creation_timestamp${COLOR_RESET}"
    echo -e "${COLOR_SOPHISTICATED}Command:${COLOR_RESET}"
    if [ -n "$command" ]; then
        echo "------"
        echo "$command" #| boxes -d stone -p a1
        echo "------"
    else
        echo -e "${COLOR_SOPHISTICATED}Command: Not specified${COLOR_RESET}"
    fi
}

get_events_by_resource_type_and_resource_name_2() {
    local namespace="$1"
    local resource_type="$2"
    local resource_name="$3"

    # Check if namespace is provided, if not, prompt for it
    if [ -z "$namespace" ]; then
        read -p "Enter the namespace (leave empty to select from available namespaces): " namespace
        if [ -z "$namespace" ]; then
            namespace=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | fzf --prompt="Select Namespace: ")
        fi
    fi

    if [ -z "$namespace" ]; then
        echo "No namespace selected."
        return
    fi

    # Check if resource type is provided, if not, prompt for it
    if [ -z "$resource_type" ]; then
        resource_type=$(kubectl -n "$namespace" api-resources --no-headers 2>/dev/null \
            | while read line; do
                if [ $(echo $line | wc -w) -ge 5 ]; then
                    echo $line | awk '{print $5}'
                fi
            done | fzf --prompt="Select Resource Type: ")
    fi

    if [ -z "$resource_type" ]; then
        echo "No resource type selected."
        return
    fi

    #  Check if resource name is provided, if not, prompt for it
    if [ -z "$resource_name" ]; then
        resource_name=$(kubectl -n "$namespace" get "$resource_type" -o name 2>/dev/null | fzf --prompt="Select $resource_type: ")
    fi

    if [ -z "$resource_name" ]; then
        echo "No resource selected."
        return
    fi

    echo "Fetching events for resource: $resource_name of type: $resource_type in namespace: $namespace"
    if [ -z "$events_json" ]; then
        echo "No events found for resource: $resource_name of type: $resource_type in namespace: ${namespace:-default}"
        return
    else
        events_json=$(kubectl -n "$namespace" get events --field-selector involvedObject.kind="$resource_type",involvedObject.name="${resource_name#*/}" -o json 2>/dev/null | jq '.items[] | select(.type != "Normal")')

        local max_last_seen=0
        local max_type=0
        local max_reason=0
        local max_message=0

        while read -r last_seen type reason message; do
            ((${#last_seen} > max_last_seen)) && max_last_seen=${#last_seen}
            ((${#type} > max_type)) && max_type=${#type}
            ((${#reason} > max_reason)) && max_reason=${#reason}
            ((${#message} > max_message)) && max_message=${#message}
        done < <(echo "$events_json" | jq -r '[
            (.lastTimestamp // .eventTime // "N/A"),
            (.type // "N/A"),
            (.reason // "N/A"),
            (.message // "N/A" | gsub("\n"; " "))
        ] | @tsv')

        printf "Events for %s in namespace %s:\n" "$resource_name" "$namespace"
        printf "  > %-*s %-*s %-*s %-s\n" $max_last_seen "LAST SEEN" $max_type "TYPE" $max_reason "REASON" "MESSAGE"
        printf "  > %s\n" "$(printf "%-${max_last_seen}s %-${max_type}s %-${max_reason}s %s" "" "" "" "" | tr ' ' '-')"

        while read -r last_seen type reason message; do
            # Determine the color based on the type
            case "$type" in
                Normal) color=$COLOR_NORMAL ;;
                Warning) color=$COLOR_WARNING ;;
                Error) color=$COLOR_ERROR ;;
                *) color=$COLOR_LIGHT ;; # Light color for all other types
            esac

            printf "  > %-*s %-*s %-*s %b%s%b\n" \
                $max_last_seen "$last_seen" $max_type "$type" $max_reason "$reason" "$color" "$message" "$COLOR_RESET"
        done < <(echo "$events_json" | jq -r '[
            (.lastTimestamp // .eventTime // "N/A"),
            (.type // "N/A"),
            (.reason // "N/A"),
            (.message // "N/A" | gsub("\n"; " "))
        ] | @tsv')
    fi
}

get_events_by_resource_type_and_resource_name() {
    local namespace="$1"
    local resource_type="$2"
    local resource_name="$3"
    if [ -z "$namespace" ]; then
        read -p "Enter the namespace (leave empty to select from available namespaces): " namespace
        if [ -z "$namespace" ]; then
            namespace=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | fzf --prompt="Select Namespace: ")
        fi
    fi

    if [ -z "$namespace" ]; then
        echo "No namespace selected."
        return
    fi

    if [ -z "$resource_type" ]; then
        resource_type=$(kubectl -n "$namespace" api-resources --no-headers 2>/dev/null \
            | while read line; do
                if [ $(echo $line | wc -w) -ge 5 ]; then
                    echo $line | awk '{print $5}'
                fi
            done | fzf --prompt="Select Resource Type: ")
    fi
    if [ -z "$resource_type" ]; then
        echo "No resource type selected."
        return
    fi

    if [ -z "$resource_name" ]; then
        resource_name=$(kubectl -n "$namespace" get "$resource_type" -o name 2>/dev/null | fzf --prompt="Select $resource_type: ")
    fi
    if [ -z "$resource_name" ]; then
        echo "No resource selected."
        return
    fi
    events_json=$(kubectl -n "$namespace" get events --field-selector involvedObject.kind="$resource_type",involvedObject.name="${resource_name#*/}" -o json 2>/dev/null | jq '.items[] | select(.type != "Normal")')

    result_events=$(kubectl -n "$namespace" get events --field-selector involvedObject.kind="$resource_type",involvedObject.name="${resource_name#*/}" -o json 2>/dev/null \
        | jq -r '.items[] | select(.type != "Normal" or (.reason | test("error|exception|fail|critical|BackOff|Error|Failed|CrashLoopBackOff|Warning"))) | "[" + .reason + "] " + (.message | split(" ")[0:10] | join(" "))')

    result_logs=$(kubectl logs "$resource_name" -n "$namespace" 2>/dev/null | grep -iE "error|exception|fail|critical|Unhealthy|Error|Failed|ImagePullBackOff|CrashLoopBackOff|OOMKilled|Connection refused" 2>/dev/null)
    if [[ ${result_logs} != "" ]]; then
        echo "${result_logs}" | while read log; do
            echo -e "       ├ ${COLOR_LIGHT_RED}[log] $log${RESET}"
        done
    fi
    if [[ ${result_events} != "" ]]; then
        echo "${result_events}" | while read event; do
            echo -e "       ├ ${ORANGE}[event] $event${RESET}"
        done
    fi
    if [[ ${result_events} == "" && ${result_logs} == "" ]]; then
        echo -e "        » no event / log error for $resource_name "
    fi
}

print_k8s_pod_events_aligned() {
    local namespace=$1
    local pod_name=$2

    events_json=$(kubectl -n "$namespace" get events --field-selector involvedObject.kind=Pod,involvedObject.name="$pod_name" -o json | jq '.items[] | select(.type != "Normal")')

    local max_last_seen=0
    local max_type=0
    local max_reason=0
    local max_message=0

    while read -r last_seen type reason message; do
        ((${#last_seen} > max_last_seen)) && max_last_seen=${#last_seen}
        ((${#type} > max_type)) && max_type=${#type}
        ((${#reason} > max_reason)) && max_reason=${#reason}
        ((${#message} > max_message)) && max_message=${#message}
    done < <(echo "$events_json" | jq -r '[
        (.lastTimestamp // .eventTime // "N/A"),
        (.type // "N/A"),
        (.reason // "N/A"),
        (.message // "N/A" | gsub("\n"; " "))
    ] | @tsv')

    printf "Events for Pod %s in namespace %s:\n" "$pod_name" "$namespace"
    printf "  > %-*s %-*s %-*s %-s\n" $max_last_seen "LAST SEEN" $max_type "TYPE" $max_reason "REASON" "MESSAGE"
    printf "  > %s\n" "$(printf "%-${max_last_seen}s %-${max_type}s %-${max_reason}s %s" "" "" "" "" | tr ' ' '-')"

    while read -r last_seen type reason message; do
        printf "  > %-*s %-*s %-*s %-s\n" \
            $max_last_seen "$last_seen" $max_type "$type" $max_reason "$reason" "$message"
    done < <(echo "$events_json" | jq -r '[
        (.lastTimestamp // .eventTime // "N/A"),
        (.type // "N/A"),
        (.reason // "N/A"),
        (.message // "N/A" | gsub("\n"; " "))
    ] | @tsv')
}

print_k8s_job_events_aligned() {
    local namespace=$1
    local job_name=$2

    events_json=$(kubectl -n "$namespace" get events --field-selector involvedObject.kind=Job,involvedObject.name="$job_name" -o json | jq '.items[] | select(.type != "Normal")')

    local max_last_seen=0
    local max_type=0
    local max_reason=0
    local max_message=0

    while read -r last_seen type reason message; do
        ((${#last_seen} > max_last_seen)) && max_last_seen=${#last_seen}
        ((${#type} > max_type)) && max_type=${#type}
        ((${#reason} > max_reason)) && max_reason=${#reason}
        ((${#message} > max_message)) && max_message=${#message}
    done < <(echo "$events_json" | jq -r '[
        (.lastTimestamp // .eventTime // "N/A"),
        (.type // "N/A"),
        (.reason // "N/A"),
        (.message // "N/A" | gsub("\n"; " "))
    ] | @tsv')

    printf "-- Events for Job %s in namespace %s:\n" "$job_name" "$namespace"
    printf "  > %-*s %-*s %-*s %-s\n" $max_last_seen "LAST SEEN" $max_type "TYPE" $max_reason "REASON" "MESSAGE"
    printf "  > %s\n" "$(printf "%-${max_last_seen}s %-${max_type}s %-${max_reason}s %s" "" "" "" "" | tr ' ' '-')"

    while read -r last_seen type reason message; do
        printf "  > %-*s %-*s %-*s %-s\n" \
            $max_last_seen "$last_seen" $max_type "$type" $max_reason "$reason" "$message"
    done < <(echo "$events_json" | jq -r '[
        (.lastTimestamp // .eventTime // "N/A"),
        (.type // "N/A"),
        (.reason // "N/A"),
        (.message // "N/A" | gsub("\n"; " "))
    ] | @tsv')
}

print_k8s_cronjob_events_aligned() {
    local namespace=$1
    local cronjob_name=$2

    events_json=$(kubectl -n "$namespace" get events --field-selector involvedObject.kind=CronJob,involvedObject.name="$cronjob_name" -o json | jq '.items[] | select(.type != "Normal")')

    local max_last_seen=0
    local max_type=0
    local max_reason=0
    local max_message=0

    while read -r last_seen type reason message; do
        ((${#last_seen} > max_last_seen)) && max_last_seen=${#last_seen}
        ((${#type} > max_type)) && max_type=${#type}
        ((${#reason} > max_reason)) && max_reason=${#reason}
        ((${#message} > max_message)) && max_message=${#message}
    done < <(echo "$events_json" | jq -r '[
        (.lastTimestamp // .eventTime // "N/A"),
        (.type // "N/A"),
        (.reason // "N/A"),
        (.message // "N/A" | gsub("\n"; " "))
    ] | @tsv')

    printf "-- Events for CronJob %s in namespace %s:\n" "$cronjob_name" "$namespace"
    printf "  > %-*s %-*s %-*s %-s\n" $max_last_seen "LAST SEEN" $max_type "TYPE" $max_reason "REASON" "MESSAGE"
    printf "  > %s\n" "$(printf "%-${max_last_seen}s %-${max_type}s %-${max_reason}s %s" "" "" "" "" | tr ' ' '-')"

    while read -r last_seen type reason message; do
        printf "  > %-*s %-*s %-*s %-s\n" \
            $max_last_seen "$last_seen" $max_type "$type" $max_reason "$reason" "$message"
    done < <(echo "$events_json" | jq -r '[
        (.lastTimestamp // .eventTime // "N/A"),
        (.type // "N/A"),
        (.reason // "N/A"),
        (.message // "N/A" | gsub("\n"; " "))
    ] | @tsv')
}
