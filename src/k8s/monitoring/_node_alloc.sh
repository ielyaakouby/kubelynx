#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
monitor_node_allocated_resources() {
    local node_name
    node_name=$(select_node_name)
    if [[ -z "$node_name" ]]; then
        echo "❌ Node name is empty. Exiting..."
        return 1
    fi

    local LIGHT_BLUE="\033[1;34m"
    local LIGHT_GREEN="\033[1;32m"
    local LIGHT_RED="\033[1;31m"
    local RESET="\033[0m"

    echo -e "\n${LIGHT_BLUE}====  =================================${RESET}"
    echo -e "${LIGHT_BLUE}==== Allocated resources of node ${LIGHT_GREEN}$node_name${LIGHT_BLUE} ================================${RESET}"
    echo -e "${LIGHT_BLUE}==== (Total limits may be over 100 percent, i.e., overcommitted.) =====${RESET}"

    while true; do
        local now alerts=()
        now=$(date '+%a %b %d %T %Z %Y')
        echo -e "\n${LIGHT_GREEN}  ~~~~~ $now ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${RESET}"

        # Temporary file for alerts
        local tmp_alerts_file
        tmp_alerts_file=$(mktemp)

        kubectl describe node "$node_name" 2>/dev/null \
            | awk -v node="$node_name" -v red="$LIGHT_RED" -v green="$LIGHT_GREEN" -v reset="$RESET" '
            BEGIN { inside=0 }

            /^Allocated resources:/ { getline; getline; inside=1; next }
            inside && /^Events:/ { exit }

            inside {
                if ($1 == "cpu" || $1 == "memory") {
                    resource=$1
                    combined = $2 " " $3
                    limit = $4

                    match(combined, /^([0-9a-zA-Z]+) \(([0-9]+)%\)$/, arr)
                    val = arr[1]
                    pct = arr[2] + 0

                    printf("      %-18s %s (%d%%)  %s\n", resource, val, pct, limit)

                    if (resource == "cpu" && pct >= 80) {
                        printf("__ALERT__CPU\n") > "/dev/stderr"
                    }
                    if (resource == "memory" && pct >= 80) {
                        printf("__ALERT__MEM\n") > "/dev/stderr"
                    }
                }
                else if ($1 == "Resource" || $1 == "--------") {
                    printf("      %s\n", $0)
                }
                else {
                    printf("      %s\n", $0)
                }
            }
        ' 2>"$tmp_alerts_file"

        while read -r line; do
            case "$line" in
                __ALERT__CPU)
                    alerts+=("⚠️  CPU usage on node $node_name exceeds 80%")
                    ;;
                __ALERT__MEM)
                    alerts+=("⚠️  MEMORY usage on node $node_name exceeds 80%")
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

        sleep 3
    done
}

# Percentage display
