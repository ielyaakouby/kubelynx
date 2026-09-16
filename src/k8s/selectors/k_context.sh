#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
get_contexts() {
    kubectl config get-contexts -o=name
}

select_context() {
    local contexts
    contexts=$(get_contexts)
    echo "$contexts" | fzf --height 40% --border --prompt="🎯 Select context: "
}
