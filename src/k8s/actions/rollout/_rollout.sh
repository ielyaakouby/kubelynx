#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
# Spinner wrapper with status output
check_snipp() {
    local message="$1"
    local command="$2"
    local delay=0.1 spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

    echo -n "⠿ $message... "

    spinner() {
        local pid="$1"
        while kill -0 "$pid" 2>/dev/null; do
            for ((i = 0; i < ${#spin}; i++)); do
                printf "\r%s %s..." "${spin:$i:1}" "$message"
                sleep "$delay"
            done
        done
    }

    bash -c "$command" &>/dev/null &
    local pid=$!
    spinner "$pid" &
    local spin_pid=$!

    wait "$pid"
    local exit_code=$?
    kill "$spin_pid" &>/dev/null
    wait "$spin_pid" 2>/dev/null

    if [[ $exit_code -eq 0 ]]; then
        printf "\r\033[1;36m[✓] %s... done\033[0m\n" "$message"
    else
        printf "\r\033[1;31m[✖] %s... failed\033[0m\n" "$message"
        #exit 1
    fi
}

# Confirm before restarting a resource
kube_confirm_rollout() {
    local type="$1" name="$2" ns="$3"
    read -rp $'\e[1;31m➤ Are you sure you want to restart the '"\"$type\" \"$name\" in namespace \"$ns\""'? (y/n): \e[0m' confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || {
        echo "❌ Rollout cancelled."
        return 1
    }
    echo
    echo "[✓] Restarting $type \"$name\" in namespace \"$ns\""
    if kubectl rollout restart "$type" "$name" -n "$ns"; then
        echo "[✓] Successfully restarted $type \"$name\" in namespace \"$ns\""
    else
        echo "❌ Failed to restart $type \"$name\" in namespace \"$ns\"" >&2
        return 1
    fi

}

# Detect resource type from a pod
kube_detect_resource_from_pod() {
    local pod="$1" ns="$2"
    local owner_name owner_kind

    owner_name=$(kubectl -n "$ns" get pod "$pod" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null)
    owner_kind=$(kubectl -n "$ns" get pod "$pod" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null)

    if [[ "$owner_kind" == "ReplicaSet" ]]; then
        local deployment
        deployment=$(kubectl -n "$ns" get replicaset "$owner_name" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null)
        echo "📦 Pod \"$pod\" is part of deployment \"$deployment\""
        echo "$deployment deployments"
    else
        local kind
        kind=$(echo "$owner_kind" | tr '[:upper:]' '[:lower:]')s
        echo "📦 Pod \"$pod\" is part of $kind \"$owner_name\""
        echo "$owner_name $kind"
    fi
}

# Main interactive function to restart deployments
kube_restart_resource() {
    local pod_name="${1:-}" ns="${2:-}" resource_name resource_type

    if [[ -n "$ns" && -n "$pod_name" ]]; then
        read -r resource_name resource_type <<<"$(kube_detect_resource_from_pod "$pod_name" "$ns")"
        kube_confirm_rollout "$resource_type" "$resource_name" "$ns"
        return
    fi

    local options=(
        "Deployment name"
        "From pod name"
        "From known resource"
    )
    local choice
    choice=$(printf '%s\n' "${options[@]}" | fzf --prompt "🔧 Choose rollout method: ") || return

    case "$choice" in
        "Deployment name")
            ns=$(select_namespace) || return
            resource_name=$(select_deployment "$ns") || return
            resource_type="deployments"
            ;;
        "From pod name")
            pod_name=$(select_pod) || return
            ns=$(select_namespace) || return
            read -r resource_name resource_type <<<"$(kube_detect_resource_from_pod "$pod_name" "$ns")"
            ;;
        "From name pattern")
            ns=$(select_namespace) || return
            read -rp "  → Enter a name pattern (e.g. api, frontend, nginx): " pattern
            [[ -z "$pattern" ]] && echo "❌ No pattern entered." && return

            resource_name=$(kubectl -n "$ns" get deploy -o name | grep "$pattern" | sed 's|deployment.apps/||' | fzf --prompt "🎯 Select matching deployment ❯ ") || return
            resource_type="deployments"

            ;;
        *)
            echo "❌ Invalid option." && return 1
            ;;
    esac

    kube_confirm_rollout "$resource_type" "$resource_name" "$ns"
}

kube_restart_deployment() {
    local ns deploy line

    ns=$(select_namespace) || return

    if [[ "$ns" == "all" ]]; then
        line=$(select_resource_global "deployment") || return
        ns=$(awk '{print $1}' <<<"$line")
        deploy=$(awk '{print $2}' <<<"$line")
    else
        deploy=$(select_deployment "$ns") || return
    fi

    echo -e "${CLR_INFO}[i] deployment: $deploy - namespace: $ns${CLR_RESET}"

    if kubectl -n "$ns" rollout restart deployment "$deploy" &>/dev/null; then
        echo -e "${CLR_SUCCESS}[✓] Restarted successfully${CLR_RESET}"
    else
        echo -e "${CLR_ERROR}❌ Failed to restart${CLR_RESET}" >&2
        return 1
    fi
}

select_resource_global() {
    local resource_type="$1"
    local prompt="${2:-📦 Select $resource_type from any namespace:}"

    local line
    line=$(kubectl get "$resource_type" --all-namespaces \
        -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name" --no-headers \
        | fzf --prompt "$prompt ") || return 1

    local ns name
    ns=$(awk '{print $1}' <<<"$line")
    name=$(awk '{print $2}' <<<"$line")

    echo "$ns;$name"
}

kube_scale_deployment() {
    local ns deploy line replicas

    ns=$(select_namespace) || return

    if [[ "$ns" == "all" ]]; then
        IFS=";" read -r ns deploy < <(select_resource_global "deploy" "📦 Select deployment from any namespace:") || return
    else
        deploy=$(select_deployment "$ns") || return
    fi

    read -rp "  → Enter desired replica count: " replicas
    if [[ -z "$replicas" ]]; then
        frame_message "${RED}" "❌ No replica count entered."
        return 1
    fi

    echo
    echo -e "${CLR_INFO}[i] deployment: $deploy - namespace: $ns - desired replica: $replicas${CLR_RESET}"

    if kubectl -n "$ns" scale deployment "$deploy" --replicas="$replicas" &>/dev/null; then
        echo -e "${CLR_SUCCESS}[✓] Scaled successfully${CLR_RESET}"
    else
        echo -e "${CLR_ERROR}❌ Failed to scale${CLR_RESET}" >&2
        return 1
    fi
}

kube_rollback_deployment() {
    local ns deploy history revisions rev details confirm

    ns=$(select_namespace) || return

    if [[ "$ns" == "all" ]]; then
        IFS=";" read -r ns deploy < <(select_resource_global "deploy" "📦 Select deployment from any namespace:") || return
    else
        deploy=$(select_deployment "$ns") || return
    fi

    print_separator

    history=$(kubectl -n "$ns" rollout history deployment "$deploy" 2>/dev/null)
    if [[ -z "$history" || "$history" != *"REVISION"* ]]; then
        echo -e "${CLR_ERROR}⚠️  No rollout history found for \"$deploy\" in \"$ns\".${CLR_RESET}"
        return 1
    fi

    echo -e "${CLR_SUCCESS}[✓] Rollout history for \"$deploy\" in \"$ns\":${CLR_RESET}"
    echo "$history"
    echo "------------------------------------------------------------"

    revisions=$(echo "$history" | awk '/^[0-9]+/ {print $1}')
    rev=$(echo "$revisions" | fzf --prompt="⏪ Choose revision to rollback ❯ ") || return

    echo -e "${CLR_INFO}[i] deployment: $deploy - namespace: $ns - target revision: $rev${CLR_RESET}"
    echo
    echo -e "${CLR_INFO}[i] Fetching details for revision ${rev}...${CLR_RESET}"
    details=$(kubectl -n "$ns" rollout history deployment "$deploy" --revision="$rev" 2>/dev/null)

    if [[ -n "$details" ]]; then
        echo "------------------------------------------------------------"
        echo "$details"
        echo "------------------------------------------------------------"
    else
        echo -e "${CLR_ERROR}⚠️  Unable to retrieve details for revision $rev.${CLR_RESET}"
        return 1
    fi

    echo
    read -rp "[+]  Confirm rollback to revision $rev? (y/N): " confirm
    if [[ "$confirm" != [yY] ]]; then
        echo -e "${CLR_WARN}[x] Rollback aborted.${CLR_RESET}"
        return 0
    fi

    echo
    if kubectl -n "$ns" rollout undo deployment "$deploy" --to-revision="$rev" &>/dev/null; then
        echo -e "${CLR_SUCCESS}[✓] Rolled back successfully${CLR_RESET}"
    else
        echo -e "${CLR_ERROR}❌ Failed to rollback${CLR_RESET}" >&2
        return 1
    fi
}

kube_rollout_history() {
    local ns=$(select_namespace) || return
    local deploy=$(select_deployment "$ns") || return
    local message="Fetching rollout history for \"$deploy\" in \"$ns\""
    local delay=0.1
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    echo -n "⠿ $message... "

    local tmp_output
    tmp_output=$(create_temp_file "_rollout-history.txt")

    bash -c "kubectl -n \"$ns\" rollout history deployment \"$deploy\"" >"$tmp_output" 2>&1 &
    local pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        i=$(((i + 1) % ${#spin}))
        printf "\r%s %s..." "${spin:$i:1}" "$message"
        sleep "$delay"
    done

    wait "$pid"
    local exit_code=$?
    local output
    output=$(<"$tmp_output")
    rm -f "$tmp_output"

    if [ $exit_code -eq 0 ]; then
        printf "\r\033[1;36m[✓] %s... done\033[0m\n\n" "$message"
        echo "$output" | column -t
        echo -e "\n\033[0;90m──────────────────────────────────────────────────────────────\033[0m"
    else
        printf "\r\033[1;31m[✖] %s... failed\033[0m\n\n" "$message"
        echo "$output"
        return 1
    fi
}

# Rollout history display
