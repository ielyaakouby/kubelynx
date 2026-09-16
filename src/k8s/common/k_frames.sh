#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
frame_message_namespace_selected() {
    NAMESPACE="$1"
    if [[ -z $NAMESPACE ]]; then
        NAMESPACE=$(select_namespace) || exit 1
        if [[ -z $NAMESPACE ]]; then
            echo "namespace is empty. Exiting..."
            return 1
        fi
        frame_message_1 "${GREEN}" "[✓] Selected Namespace: $NAMESPACE"
    fi
}

frame_message_1() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

print_separator() {
    echo -e "${YELLOW}──────────────────────────────────────────────${NC}"
}

#frame_message() { echo -e "${1}${2}${RESET}"; }
#print_separator() { printf "\n%s\n" "${CYAN}──────────────────────────────────────────────${RESET}"; }

print_separator_with_date() {
    echo -e "${YELLOW}$(date '+%Y/%m/%d at %H:%M:%S') <---------------------------|${NC}"
}

print_full_line() {
    local char="${1:-*}" # Default character is '*'
    printf '%*s\n' "$(tput cols)" '' | tr ' ' "$char"
}
# Improved frame rendering
