#!/usr/bin/env bash
# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
# Placeholders for shared temp-file variables owned by bin/kubelynx.sh.
# Do not overwrite values already set by the entrypoint.
: "${OK_FILE:=}"
: "${NOK_FILE:=}"
: "${TMP_ALL_PODS:=}"
: "${TMP_NODE_REPORT:=}"
: "${TMP_NODE_COUNTS:=}"
