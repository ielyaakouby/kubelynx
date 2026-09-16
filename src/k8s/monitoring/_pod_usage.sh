#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
# Dependencies: kubectl, jq, fzf

monitor_pod_resources() {
    ensure_pod_and_namespace || return 1
    [[ -z "$NAMESPACE" || -z "$POD_NAME" ]] && {
        echo "Namespace or pod name missing."
        return 1
    }

    echo -e "\n${YELLOW}Namespace:${RESET} $NAMESPACE"
    echo -e "${YELLOW}Pod:${RESET} $POD_NAME"

    kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o json | jq -r '
        .spec.containers[] | "Container: \(.name)\nCPU: Limit \(.resources.limits.cpu // \"N/A\") | Request \(.resources.requests.cpu // \"N/A\")\nMemory: Limit \(.resources.limits.memory // \"N/A\") | Request \(.resources.requests.memory // \"N/A\")\n"
    '

    echo -e "${LIGHT_BLUE}\nStarting resource monitoring (Ctrl+C to stop)...${RESET}"
    while true; do
        echo -e "\n${YELLOW}==== $(date) ====================================${RESET}"
        top_output=$(kubectl top pod "$POD_NAME" -n "$NAMESPACE" --containers --use-protocol-buffers 2>/dev/null)
        echo -e "${GREEN}$top_output${RESET}"

        total_cpu=$(echo "$top_output" | awk 'NR>1 {sum+=$3} END {print sum}')
        total_mem=$(echo "$top_output" | awk 'NR>1 {sum+=$4} END {print sum}')

        echo -e "${LIGHT_BLUE}Total CPU:${RESET} ${LIGHT_RED}${total_cpu:-0}m${RESET}"
        echo -e "${LIGHT_BLUE}Total Memory:${RESET} ${LIGHT_RED}${total_mem:-0}Mi${RESET}"

        sleep 5
    done
}

get_pod_limits_requests() {
    ensure_pod_and_namespace || return 1

    local pod_json
    pod_json=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o json)
    [[ -z "$pod_json" ]] && {
        echo -e "${RED}Failed to retrieve pod data.${RESET}"
        return 1
    }

    jq -r '
        .spec.containers[] | "Container: \(.name)\n  Limits:\n    CPU: \(.resources.limits.cpu // \"Not Set\")\n    Memory: \(.resources.limits.memory // \"Not Set\")\n  Requests:\n    CPU: \(.resources.requests.cpu // \"Not Set\")\n    Memory: \(.resources.requests.memory // \"Not Set\")\n"
    ' <<<"$pod_json"
}

monitor_pod_usage_over_time() {
    local duration unit value namespace pod_name pattern resource
    local LIGHT_RED="\033[1;31m" LIGHT_GREEN="\033[1;32m"
    local LIGHT_YELLOW="\033[1;33m" LIGHT_CYAN="\033[1;36m" RESET="\033[0m"

    # Vérification des prérequis
    if ! command -v kubectl &>/dev/null; then
        echo -e "${LIGHT_RED}❌ kubectl n'est pas installé ou n'est pas dans le PATH${RESET}"
        return 1
    fi

    # Saisie de la durée
    read -rp "⏱️  Duration (e.g., 120s, 2h, 3m, 1d): " duration
    [[ -z "$duration" ]] && {
        echo -e "${LIGHT_RED}❌ Duration is required.${RESET}"
        return 1
    }

    # Conversion de la durée en secondes
    unit="${duration: -1}"
    value="${duration%"$unit"}"
    case "$unit" in
        s) duration=$value ;;
        m) duration=$((value * 60)) ;;
        h) duration=$((value * 3600)) ;;
        d) duration=$((value * 86400)) ;;
        *)
            echo -e "${LIGHT_RED}❌ Invalid duration unit. Use s, m, h or d.${RESET}"
            return 1
            ;;
    esac

    # Sélection du namespace
    #    echo -e "${LIGHT_YELLOW}📦 Select a namespace (or press Enter to choose interactively):${RESET}"
    #    read -rp "Namespace: " namespace
    read -rp "$(echo -e "${LIGHT_YELLOW}📦 Select a namespace (or press Enter to choose interactively): ${RESET}")" namespace

    if [[ -z "$namespace" ]]; then
        namespace=$( (
            echo "all"
            kubectl get ns --no-headers 2>/dev/null | awk '{print $1}'
        ) | fzf --prompt="📦 Select a namespace (or 'all'): ")
        [[ -z "$namespace" ]] && {
            echo -e "${LIGHT_RED}❌ No namespace selected.${RESET}"
            return 1
        }
    fi

    # Vérification que le namespace existe
    if [[ "$namespace" != "all" ]] && ! kubectl get ns "$namespace" &>/dev/null; then
        echo -e "${LIGHT_RED}❌ Namespace '$namespace' does not exist.${RESET}"
        return 1
    fi

    # Sélection du pod
    read -rp "🔍 Pod pattern (or press Enter to choose interactively): " pattern
    if [[ -z "$pattern" ]]; then
        echo "1"
        if [[ "$namespace" == "all" ]]; then
            echo "11"
            pod_info=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | fzf --prompt="🩺 Select pod: ")
            [[ -z "$pod_info" ]] && {
                echo -e "${LIGHT_RED}❌ No pod selected.${RESET}"
                return 1
            }
            pod_name=$(awk '{print $2}' <<<"$pod_info")
            namespace=$(awk '{print $1}' <<<"$pod_info")
        else
            echo "111"
            pod_name=$(kubectl -n "$namespace" get pods --no-headers 2>/dev/null | fzf --prompt="🩺 Select pod: " | awk '{print $1}')
            [[ -z "$pod_name" ]] && {
                echo -e "${LIGHT_RED}❌ No pod selected.${RESET}"
                return 1
            }
        fi
    else
        echo "2"
        if [[ "$namespace" == "all" ]]; then
            echo "22"
            pod_info=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | grep -m1 "$pattern" | fzf --prompt="🩺 Select pod: ")
            [[ -z "$pod_info" ]] && {
                echo -e "${LIGHT_RED}❌ No pod matching pattern '$pattern' found.${RESET}"
                return 1
            }
            pod_name=$(awk '{print $2}' <<<"$pod_info")
            namespace=$(awk '{print $1}' <<<"$pod_info")
            echo "pod_name: $pod_name"
            echo "ns: $namespace"
        else
            echo "222"
            pod_name=$(kubectl -n "$namespace" get pods --no-headers 2>/dev/null | grep -m1 "$pattern" | awk '{print $1}' | fzf --prompt="🩺 Select pod: " | awk '{print $1}')
            [[ -z "$pod_name" ]] && {
                echo -e "${LIGHT_RED}❌ No pod matching pattern '$pattern' found in namespace '$namespace'.${RESET}"
                return 1
            }
        fi
    fi

    # Vérification que le pod existe
    if ! kubectl -n "$namespace" get pod "$pod_name" &>/dev/null; then
        echo -e "${LIGHT_RED}❌ Pod '$pod_name' does not exist in namespace '$namespace'.${RESET}"
        return 1
    fi

    # Sélection de la ressource à surveiller
    resource=$(echo -e "CPU\nMemory\nBoth" | fzf --prompt="🩺 Select resource type: ")
    [[ -z "$resource" ]] && {
        echo -e "${LIGHT_RED}❌ No resource type selected.${RESET}"
        return 1
    }

    # Vérification que metrics-server est installé
    if ! kubectl top pods --help &>/dev/null; then
        echo -e "${LIGHT_RED}❌ metrics-server n'est pas installé ou ne fonctionne pas correctement.${RESET}"
        echo -e "Installez-le avec: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
        return 1
    fi

    # Récupération des ressources du pod
    echo -e "\n${LIGHT_CYAN}🔍 Fetching container resource definitions...${RESET}"
    pod_desc=$(kubectl -n "$namespace" get pod "$pod_name" -o json 2>/dev/null)
    if [[ -z "$pod_desc" ]]; then
        echo -e "${LIGHT_RED}❌ Failed to get pod description.${RESET}"
        return 1
    fi

    # Calcul des ressources totales
    cpu_request_total=0
    cpu_limit_total=0
    mem_request_total=0
    mem_limit_total=0
    has_cpu_request=false
    has_cpu_limit=false
    has_mem_request=false
    has_mem_limit=false

    while IFS= read -r row; do
        cpu_req=$(jq -r '.resources.requests.cpu // empty' <<<"$row")
        cpu_lim=$(jq -r '.resources.limits.cpu // empty' <<<"$row")
        mem_req=$(jq -r '.resources.requests.memory // empty' <<<"$row")
        mem_lim=$(jq -r '.resources.limits.memory // empty' <<<"$row")

        # CPU requests
        if [[ -n "$cpu_req" ]]; then
            if [[ "$cpu_req" =~ m$ ]]; then
                cpu_val=${cpu_req%m}
            else
                cpu_val=$(awk "BEGIN {printf \"%d\", $cpu_req * 1000}")
            fi
            ((cpu_request_total += cpu_val))
            has_cpu_request=true
        fi

        # CPU limits
        if [[ -n "$cpu_lim" ]]; then
            if [[ "$cpu_lim" =~ m$ ]]; then
                cpu_val=${cpu_lim%m}
            else
                cpu_val=$(awk "BEGIN {printf \"%d\", $cpu_lim * 1000}")
            fi
            ((cpu_limit_total += cpu_val))
            has_cpu_limit=true
        fi

        # Memory requests
        if [[ -n "$mem_req" ]]; then
            mem_val=$(echo "$mem_req" | sed 's/[^0-9]*//g')
            ((mem_request_total += mem_val))
            has_mem_request=true
        fi

        # Memory limits
        if [[ -n "$mem_lim" ]]; then
            mem_val=$(echo "$mem_lim" | sed 's/[^0-9]*//g')
            ((mem_limit_total += mem_val))
            has_mem_limit=true
        fi
    done < <(jq -c '.spec.containers[]' <<<"$pod_desc")

    # Affichage des ressources
    cpu_request_display=$([[ "$has_cpu_request" == true ]] && echo "${cpu_request_total}m" || echo "N/A")
    cpu_limit_display=$([[ "$has_cpu_limit" == true ]] && echo "${cpu_limit_total}m" || echo "N/A")
    mem_request_display=$([[ "$has_mem_request" == true ]] && echo "${mem_request_total}Mi" || echo "N/A")
    mem_limit_display=$([[ "$has_mem_limit" == true ]] && echo "${mem_limit_total}Mi" || echo "N/A")

    echo -e "\n${LIGHT_CYAN}📊 Monitoring Pod Usage for $duration seconds...${RESET}"
    echo -e "${LIGHT_GREEN}Pod:        ${RESET}$pod_name"
    echo -e "${LIGHT_GREEN}Namespace:  ${RESET}$namespace"
    echo -e "${LIGHT_GREEN}CPU Req:    ${RESET}$cpu_request_display"
    echo -e "${LIGHT_GREEN}CPU Limit:  ${RESET}$cpu_limit_display"
    echo -e "${LIGHT_GREEN}Mem Req:    ${RESET}$mem_request_display"
    echo -e "${LIGHT_GREEN}Mem Limit:  ${RESET}$mem_limit_display"
    echo -e "${LIGHT_GREEN}Duration:   ${RESET}$duration seconds"
    echo -e "${LIGHT_GREEN}Start Time: ${RESET}$(date '+%Y-%m-%d %H:%M:%S')\n"

    # Démarrer la surveillance
    max_cpu=0
    total_cpu=0
    count=0
    max_mem=0
    total_mem=0
    start_time_=$(date '+%Y-%m-%d %H:%M:%S')

    for ((i = 1; i <= duration; i++)); do
        # Récupérer les métriques
        if [[ "$namespace" == "all" ]]; then
            usage=$(kubectl top pods -A --no-headers 2>/dev/null | grep "$pod_name")
        else
            usage=$(kubectl -n "$namespace" top pods --no-headers 2>/dev/null | grep "$pod_name")
        fi

        if [[ -z "$usage" ]]; then
            echo -e "${LIGHT_RED}⚠️  Failed to get metrics for pod $pod_name (attempt $i/$duration)${RESET}"
            sleep 1
            continue
        fi

        # Extraire les valeurs CPU et mémoire
        cpu=$(awk '{print $2}' <<<"$usage")
        mem=$(awk '{print $3}' <<<"$usage")
        cpu_val=$(tr -dc '0-9' <<<"$cpu")
        mem_val=$(tr -dc '0-9' <<<"$mem")
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')

        # Afficher les métriques
        output="${LIGHT_YELLOW}[$timestamp]${RESET}"
        if [[ "$resource" =~ CPU|Both ]]; then
            output+=" CPU: ${LIGHT_RED}${cpu}${RESET}"
            ((cpu_val > max_cpu)) && max_cpu=$cpu_val
            total_cpu=$((total_cpu + cpu_val))
        fi
        if [[ "$resource" =~ Memory|Both ]]; then
            output+=" Memory: ${LIGHT_RED}${mem}${RESET}"
            ((mem_val > max_mem)) && max_mem=$mem_val
            total_mem=$((total_mem + mem_val))
        fi
        echo -e "$output"

        count=$((count + 1))
        sleep 1
    done

    # Afficher le résumé
    end_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "\n${LIGHT_CYAN}🧾 Monitoring Summary:${RESET}"
    echo -e "${LIGHT_GREEN}Pod:        ${RESET}$pod_name"
    echo -e "${LIGHT_GREEN}Namespace:  ${RESET}$namespace"
    echo -e "${LIGHT_GREEN}Start Time: ${RESET}$start_time_"
    echo -e "${LIGHT_GREEN}End Time:   ${RESET}$end_time"
    echo -e "${LIGHT_GREEN}Duration:   ${RESET}$duration seconds"
    echo -e "${LIGHT_GREEN}Samples:    ${RESET}$count/$duration"

    if [[ "$resource" =~ CPU|Both ]] && [[ $count -gt 0 ]]; then
        avg_cpu=$((total_cpu / count))
        echo -e "\n${LIGHT_YELLOW}CPU Usage:${RESET}"
        echo -e "${LIGHT_GREEN}Max:       ${RESET}${max_cpu}m"
        echo -e "${LIGHT_GREEN}Avg:       ${RESET}${avg_cpu}m"
        echo -e "${LIGHT_GREEN}Request:   ${RESET}${cpu_request_display}"
        echo -e "${LIGHT_GREEN}Limit:     ${RESET}${cpu_limit_display}"
    fi

    if [[ "$resource" =~ Memory|Both ]] && [[ $count -gt 0 ]]; then
        avg_mem=$((total_mem / count))
        echo -e "\n${LIGHT_YELLOW}Memory Usage:${RESET}"
        echo -e "${LIGHT_GREEN}Max:       ${RESET}${max_mem}Mi"
        echo -e "${LIGHT_GREEN}Avg:       ${RESET}${avg_mem}Mi"
        echo -e "${LIGHT_GREEN}Request:   ${RESET}${mem_request_display}"
        echo -e "${LIGHT_GREEN}Limit:     ${RESET}${mem_limit_display}"
    fi
}

kube_top_pods() {
    local ns sort_choice display_mode head_count

    ns=$(select_namespace) || return 1

    sort_choice=$(printf "cpu\nmemory" | fzf --prompt="📊 Sort by (CPU or Memory) > ")
    [[ -z "$sort_choice" ]] && echo "❌ No sort metric selected." && return 1

    display_mode=$(printf "All Pods (sorted)\nTop X Pods (head)" | fzf --prompt="📈 Choose display mode > ")
    [[ -z "$display_mode" ]] && echo "❌ No display mode selected." && return 1

    if [[ "$display_mode" == "Top X Pods (head)" ]]; then
        read -rp "🔢 How many top pods to display? " head_count
        [[ -z "$head_count" || "$head_count" -le 0 ]] && echo "❌ Invalid count." && return 1
    fi

    echo -e "\n📊 Showing top pods sorted by $sort_choice in namespace: $ns"

    local -a top_args=(top pod --sort-by="$sort_choice")
    if [[ "$ns" == "all" ]]; then
        top_args+=(--all-namespaces)
    else
        top_args+=(-n "$ns")
    fi

    if [[ "$display_mode" == "Top X Pods (head)" ]]; then
        kubectl "${top_args[@]}" | head -n "$((head_count + 1))"
    else
        kubectl "${top_args[@]}"
    fi
}

kube_top_nodes() {
    local sort_choice display_mode head_count

    sort_choice=$(printf "cpu\nmemory" | fzf --prompt="📊 Sort by (CPU or Memory) > ")
    [[ -z "$sort_choice" ]] && echo "❌ No sort metric selected." && return 1

    display_mode=$(printf "All Nodes (sorted)\nTop X Nodes (head)" | fzf --prompt="📈 Choose display mode > ")
    [[ -z "$display_mode" ]] && echo "❌ No display mode selected." && return 1

    if [[ "$display_mode" == "Top X Nodes (head)" ]]; then
        read -rp "🔢 How many top nodes to display? " head_count
        [[ -z "$head_count" || "$head_count" -le 0 ]] && echo "❌ Invalid count." && return 1
    fi

    echo -e "\n📊 Showing top nodes sorted by $sort_choice...\n"

    if [[ "$display_mode" == "Top X Nodes (head)" ]]; then
        kubectl top nodes --sort-by="$sort_choice" | head -n "$((head_count + 1))" | column -t
    else
        kubectl top nodes --sort-by="$sort_choice" | column -t
    fi
}

# CPU/Memory threshold alerts
