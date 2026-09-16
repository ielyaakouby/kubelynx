#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
get_pods_live_logs_by_giving_one_pod() {
    local namespace="$2"

    if [[ -z $NAMESPACE ]]; then
        NAMESPACE=$(select_namespace) || exit 1
    fi
    if [[ -z "$POD_NAME" ]]; then
        POD_NAME=$(select_pod "$NAMESPACE") || exit 1
    fi

    label_list=$(kubectl -n "$NAMESPACE" get po --show-labels | grep "$pod_name" | awk '{print $NF}')

    kubectl -n "$NAMESPACE" logs -l "$label_list" --all-containers=true
}

monitor_pods_status() {
    local namespace="${1:-$(select_namespace || exit 1)}"

    # User-friendly column selection
    local column_options=(
        "NAMESPACE:namespace"
        "POD NAME:name"
        "READY:ready"
        "STATUS:status"
        "RESTARTS:restarts"
        "AGE:age"
        "IP:ip"
        "NODE:node"
    )

    # Select sort column
    local selected_column=$(printf "%s\n" "${column_options[@]}" | awk -F: '{print $1}' \
        | fzf --prompt="Select sort column: " --height=40% --layout=reverse --header="Press TAB to select")
    [ -z "$selected_column" ] && return

    # Map to kubectl field
    local sort_field
    for opt in "${column_options[@]}"; do
        if [[ "$opt" == "$selected_column:"* ]]; then
            sort_field="${opt#*:}"
            break
        fi
    done

    # Select sort order
    local sort_order=$(printf "ascending\ndescending\n" \
        | fzf --prompt="Select sort order: " --height=30% --header="Press TAB to select")
    [ -z "$sort_order" ] && return

    # Determine status field position
    local status_field=4
    [ "$namespace" = "all" ] && status_field=5

    # Build base command
    local base_cmd watch_title
    if [ "$namespace" = "all" ]; then
        base_cmd="kubectl get pods -A --no-headers"
        watch_title="Monitoring Pods in ALL namespaces"
    else
        base_cmd="kubectl get pods -n \"$namespace\" --no-headers"
        watch_title="Monitoring Pods in namespace: $namespace"
    fi

    # Apply sorting
    if [[ "$sort_field" != "age" ]]; then
        base_cmd+=" --sort-by=.${sort_field}"
        [ "$sort_order" = "descending" ] && base_cmd+=" --sort-descending"
    else
        base_cmd+=" --sort-by=.metadata.creationTimestamp"
        [ "$sort_order" = "descending" ] && base_cmd+=" --sort-descending"
    fi

    # Create a temporary script for colorization
    local color_script=$(mktemp)
    cat >"$color_script" <<'EOF'
#!/bin/bash
status_pos=$1
while read -r line; do
  if echo "$line" | awk -v pos="$status_pos" '{print $pos}' | grep -q "Running"; then
    printf "\033[32m%s\033[0m\n" "$line"
  else
    printf "\033[31m%s\033[0m\n" "$line"
  fi
done
EOF
    chmod +x "$color_script"

    # Choose display mode
    local mode=$(printf "Current terminal\nNew terminal" \
        | fzf --prompt="Open monitoring in: " --height=6 --border --reverse)

    # Build final command
    local full_cmd="$base_cmd 2>/dev/null | $color_script $status_field"
    local term_cmd="watch -t -c 'echo \"$watch_title | Sorted by: $selected_column ($sort_order)\"; $full_cmd'"

    if echo "$mode" | grep -q "New terminal"; then
        kubelynx::run_in_new_terminal "$watch_title" "$term_cmd; rm -f '$color_script'"
    else
        bash -c "$term_cmd"
        rm -f "$color_script"
    fi
}

node_status_conditions_overview() {

    local node_name
    local time_now
    node_name=$(select_node_name)
    time_now="$(date)"
    echo "==== $time_now ================================="
    while true; do
        frame_message "${BOLD}${YELLOW}" "Node Status Conditions Overview - node : $node_name" | boxes -d stone
        kubectl describe node "$node_name" 2>/dev/null \
            | awk '/Conditions:/, /^Addresses:/{if(/^Addresses:/) exit; print}' \
            | sed -n '/^ *Type/,/^ *$/p' \
            | sed '/^ *$/d'
        sleep 10
    done
}
# Refresh interval config
