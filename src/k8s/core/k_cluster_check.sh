#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
RED='\033[1;31m'
GREEN='\033[1;32m'
NC='\033[0m'

check_cluster_connectivity_snipp() {
    local message="$1"
    local command="$2"

    local delay=0.1
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    echo -n "⠿ $message... "

    bash -c "$command" &>/dev/null &
    local pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        i=$(((i + 1) % ${#spin}))
        printf "\r%s %s..." "${spin:$i:1}" "$message"
        sleep $delay
    done

    wait $pid
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        printf "\r${GREEN}[✓] %s... done${NC}\n" "$message"
        print_separator
    else
        printf "\r${RED}[✖] %s... failed${NC}\n" "$message"
        return 1
    fi
}

cluster::check_connectivity() {
    if command -v timeout >/dev/null 2>&1; then
        if ! timeout 10 kubectl cluster-info &>/dev/null; then
            echo -e "${RED}[✖] Checking cluster connectivity... failed${NC}"
            return 1
        fi
        return 0
    fi
    if ! kubectl cluster-info &>/dev/null; then
        echo -e "${RED}[✖] Checking cluster connectivity... failed${NC}"
        return 1
    fi
}

# Check API server health
