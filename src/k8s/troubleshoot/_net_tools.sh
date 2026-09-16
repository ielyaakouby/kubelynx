#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
troubleshooting_run_tool() {
    local tool_name="$1"
    local image="${2:-busybox}"

    local namespace
    namespace=$(select_namespace) || exit 1

    if [[ "$namespace" == "all" ]]; then
        frame_message "${RED}" "❌ Cannot run '$tool_name' pod in 'all' namespaces. Please select a specific namespace."
        return 1
    fi

    kubelynx::run_in_new_terminal "Troubleshooting run $tool_name in $namespace" \
        "echo '[✓] Running $tool_name-test in namespace: $namespace'; kubectl run $tool_name-test --rm -it -n \"$namespace\" --image=$image -- sh 2>/dev/null || echo 'Failed to start $tool_name-test pod.'; exec bash"
}

troubleshooting_run_curl() { troubleshooting_run_tool "curl" "curlimages/curl"; }
troubleshooting_run_ping() { troubleshooting_run_tool "ping"; }
troubleshooting_run_wget() { troubleshooting_run_tool "wget"; }
troubleshooting_run_telnet() { troubleshooting_run_tool "telnet"; }
troubleshooting_run_nslookup() { troubleshooting_run_tool "nslookup"; }

# TCP connectivity test
