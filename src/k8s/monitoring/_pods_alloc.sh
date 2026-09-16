#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
print_live_usage_header() {
    local pod_name="$1"
    local namespace="$2"
    local LIGHT_BLUE="\033[1;34m"
    local RESET="\033[0m"

    local title="📊 Monitoring: ${pod_name}  @${namespace}"
    local width=${#title}

    echo -e "${LIGHT_BLUE}${title}${RESET}"
    printf "${LIGHT_BLUE}%${width}s\n" "" | tr ' ' '-'
    #echo -e "${RESET}"
}

monitor_pod_resources_allocation() {
    ensure_pod_and_namespace

    local LIGHT_GREEN="\033[1;32m"
    local LIGHT_RED="\033[1;31m"
    local LIGHT_BLUE="\033[1;34m"
    local YELLOW="\033[1;33m"
    local RESET="\033[0m"

    # 🔍 Si namespace = all, déterminer automatiquement le bon namespace à partir du pod sélectionné
    if [[ "$NAMESPACE" == "all" ]]; then
        echo -e "${YELLOW}🔍 You selected 'all' namespaces. Searching for pod across all namespaces...${RESET}"

        if [[ -z "$POD_NAME" ]]; then
            pod_info=$(kubectl get pods --all-namespaces --no-headers | fzf --prompt="🧩 Select pod (from all namespaces): ")
            POD_NAME=$(awk '{print $2}' <<<"$pod_info")
            NAMESPACE=$(awk '{print $1}' <<<"$pod_info")
        else
            pod_info=$(kubectl get pods --all-namespaces --no-headers | grep -m1 "$POD_NAME")
            POD_NAME=$(awk '{print $2}' <<<"$pod_info")
            NAMESPACE=$(awk '{print $1}' <<<"$pod_info")
        fi

        [[ -z "$NAMESPACE" || -z "$POD_NAME" ]] && {
            echo -e "${LIGHT_RED}❌ Failed to resolve pod/namespace from selection.${RESET}"
            return 1
        }

        echo -e "${YELLOW}✅ Auto-detected Namespace:${RESET} $NAMESPACE"
        echo -e "${YELLOW}✅ Auto-detected Pod:${RESET} $POD_NAME"
    fi

    if [[ -z "$NAMESPACE" || -z "$POD_NAME" ]]; then
        echo -e "${LIGHT_RED}❌ Namespace and/or pod name is empty. Exiting...${RESET}"
        return 1
    fi

    # ⏱️ Ask for duration
    #read -rp "$(echo -e "${YELLOW}⏱️  Enter monitoring duration (e.g., 10s, 2m, 1h, 1d) or leave empty for infinite: ${RESET}")" user_duration
    #duration=0  # 0 = infinite
    while true; do
        read -rp "$(echo -e "${YELLOW}⏱️  Enter monitoring duration (e.g., 10s, 2m, 1h, 1d) or leave empty for infinite: ${RESET}")" user_duration
        if [[ -z "$user_duration" ]]; then
            duration=0
            break
        elif [[ "$user_duration" =~ ^[0-9]+[smhd]$ ]]; then
            unit="${user_duration: -1}"
            value="${user_duration::-1}"
            case "$unit" in
                s) duration=$value ;;
                m) duration=$((value * 60)) ;;
                h) duration=$((value * 3600)) ;;
                d) duration=$((value * 86400)) ;;
            esac
            break
        else
            echo -e "${LIGHT_RED}❌ Invalid format. Try again: e.g., 30s, 2m, 1h, or leave empty for infinite.${RESET}"
        fi
    done

    echo -e "\n${YELLOW}Selected Namespace:${RESET} $NAMESPACE"
    echo -e "${YELLOW}Selected Pod:${RESET} $POD_NAME"

    local start_ts=$(date +%s)

    while true; do
        local now alerts=()
        now_str=$(date '+%a %b %d %T %Z %Y')
        echo -e "\n${YELLOW}==== $now_str =================================================================${RESET}"

        tmp_alerts_file=$(mktemp)
        pod_resources=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o json 2>/dev/null)
        [[ -z "$pod_resources" ]] && {
            echo -e "${LIGHT_RED}❌ Failed to fetch pod resources.${RESET}"
            rm -f "$tmp_alerts_file"
            return 1
        }

        echo -e "${LIGHT_BLUE}### Resources per container:${RESET}"
        echo "$pod_resources" | jq -c '.spec.containers[]' | while read -r container; do
            name=$(jq -r '.name' <<<"$container")
            cpu_req=$(jq -r '.resources.requests.cpu // "0"' <<<"$container")
            cpu_lim=$(jq -r '.resources.limits.cpu // "0"' <<<"$container")
            mem_req=$(jq -r '.resources.requests.memory // "0"' <<<"$container")
            mem_lim=$(jq -r '.resources.limits.memory // "0"' <<<"$container")

            echo -e "${LIGHT_BLUE}🔹 Container: $name${RESET}"
            echo "      CPU Request:  $cpu_req"
            echo "      CPU Limit:    $cpu_lim"
            echo "      Memory Req:   $mem_req"
            echo "      Memory Limit: $mem_lim"

            cpu_pct=$(echo "$cpu_req" | awk '/m$/ {val=substr($1,1,length($1)-1); print val/1000} /^[0-9.]+$/ {print $1}')
            (($(echo "$cpu_pct >= 0.8" | bc -l))) && echo "__ALERT__CPU:$name" >>"$tmp_alerts_file"

            mem_val=$(echo "$mem_req" | sed 's/Mi//' | grep -Eo '[0-9]+')
            [[ -n "$mem_val" && "$mem_val" -ge 512 ]] && echo "__ALERT__MEM:$name" >>"$tmp_alerts_file"
        done

        while read -r line; do
            case "$line" in
                __ALERT__CPU:*)
                    cname="${line#*:}"
                    alerts+=("⚠️  CPU requests in container $cname exceed 80%")
                    ;;
                __ALERT__MEM:*)
                    cname="${line#*:}"
                    alerts+=("⚠️  MEMORY requests in container $cname exceed 512Mi")
                    ;;
            esac
        done <"$tmp_alerts_file"
        rm -f "$tmp_alerts_file"

        if [[ ${#alerts[@]} -gt 0 ]]; then
            echo
            for alert in "${alerts[@]}"; do
                echo -e "        ${LIGHT_RED}${alert}${RESET}"
            done
        fi

        print_live_usage_header "$POD_NAME" "$NAMESPACE"

        top_output=$(kubectl top pod "$POD_NAME" -n "$NAMESPACE" --containers --use-protocol-buffers 2>/dev/null)

        if [[ -z "$top_output" ]]; then
            echo -e "${LIGHT_RED}⚠️  No resource usage data available for this pod.${RESET}"
        else
            echo "$top_output" | awk -v blue="$LIGHT_BLUE" -v green="$LIGHT_GREEN" -v reset="$RESET" '
                BEGIN {
                    printf blue "\n  🧩 %-30s %-20s %-10s %-10s\n", "POD", "CONTAINER", "CPU (m)", "MEMORY" reset
                    printf blue "  ───────────────────────────────────────────────────────────────────────\n" reset
                }
                NR>1 {
                    printf green "  ⚙️  %-30s %-20s %-10s %-10s\n", $1, $2, $3, $4 reset
                    total_cpu += $3
                    sub("Mi", "", $4); total_mem += $4
                }
                END {
                    printf blue "\n  🧠 Total CPU usage:   " reset
                    printf green "%sm%s\n", total_cpu, reset

                    printf blue "  🧠 Total Memory usage: " reset
                    printf green "%sMi%s\n", total_mem, reset
                }
            '
        fi

        if [[ "$duration" -gt 0 ]]; then
            now_ts=$(date +%s)
            elapsed=$((now_ts - start_ts))
            [[ "$elapsed" -ge "$duration" ]] && break
        fi

        sleep 5
    done
}
