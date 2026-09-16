#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
new_get_pod_labels() {
    NAMESPACE="$1"

    if [[ -z $NAMESPACE ]]; then
        NAMESPACE=$(select_namespace) || exit 1
    fi

    # Use fzf to select between 1 or 2
    choice=$(echo -e "${YELLOW}1.${RESET} ${GREEN}One specific pod${RESET}\n${YELLOW}2.${RESET} ${GREEN}All pods in namespace '${NAMESPACE}'${RESET}" | fzf --height 10 --border --ansi --prompt "Select option: " --reverse)

    if [[ -z "$choice" ]]; then
        echo "Invalid choice. Exiting..."
        return 1
    fi

    if [[ "$choice" =~ "1" ]]; then
        # Use fzf to select a specific pod
        POD_NAME=$(kubectl get pods -n "$NAMESPACE" --no-headers | awk '{print $1}' | fzf --height 10 --border --ansi --prompt "Select Pod: " --reverse) || exit 1
        if [[ -z "$POD_NAME" ]]; then
            echo "Pod name is empty. Exiting..."
            return 1
        fi
        echo -e "\nLabels for Pod '$POD_NAME':"
        label_string=$(kubectl -n "${NAMESPACE}" get pod "${POD_NAME}" --show-labels --no-headers 2>/dev/null | awk '{print $NF}' | tr -d '{}"')

        if [[ -z "$label_string" ]]; then
            echo -e "${RED}No labels found for pod ${POD_NAME} in namespace ${NAMESPACE}.${RESET}"
            return 1
        fi

        echo "$label_string" | tr ',' '\n' | while read -r label; do
            echo "$label" | awk -F'=' -v red="\033[31m" -v green="\033[32m" -v reset="\033[0m" '
            {
                printf "%s%s%s: %s%s%s\n ", red,  $1, reset, green, $2, reset
            }'
        done
    elif [[ "$choice" =~ "2" ]]; then
        echo -e "\nLabels for All Pods in Namespace '$NAMESPACE':"
        kubectl -n "$NAMESPACE" get pods --no-headers | awk '{print $1}' | while read -r POD_NAME_SELECTED; do
            echo -e "\nLabels for Pod '$POD_NAME_SELECTED':\n"
            label_string=$(kubectl -n "${NAMESPACE}" get pod "${POD_NAME_SELECTED}" --show-labels --no-headers 2>/dev/null | awk '{print $NF}' | tr -d '{}"')

            if [[ -z "$label_string" ]]; then
                echo -e "${RED}No labels found for pod ${POD_NAME_SELECTED} in namespace ${NAMESPACE}.${RESET}"
                continue
            fi

            echo "$label_string" | tr ',' '\n' | while read -r label; do
                echo "$label" | awk -F'=' -v red="$RED" -v green="$GREEN" -v reset="$RESET" '
                {
                    printf "%s%s%s: %s%s%s\n", red, $1, reset, green, $2, reset
                }'
            done
        done
    else
        echo "Invalid choice. Exiting..."
        return 1
    fi
}

kubectl_get_labels() {
    NAMESPACE=$(select_namespace) || exit 1
    resource_type=$(get_resource_type)
    resource_name=$(get_resource_name "$resource_type" "$NAMESPACE")

    echo -e "${GREEN}Fetching labels for resource: $resource_name in namespace: $NAMESPACE...${RESET}"

    # Fetching labels and formatting output
    labels_output=$(kubectl -n "$NAMESPACE" get "$resource_name" -o yaml 2>/dev/null \
        | kubectl neat \
        | yq -r '.metadata.labels')

    if [[ -z "$labels_output" ]]; then
        echo -e "${GREEN}No labels found for the resource.${RESET}"
    else
        echo -e "${GREEN}Labels:${RESET}"
        echo "$labels_output" | while IFS= read -r line; do
            echo -e "  ${line}"
        done
    fi
}
