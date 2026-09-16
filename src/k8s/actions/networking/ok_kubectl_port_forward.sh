#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
kube_port_forward_pod() {
    local namespace pod local_port remote_port ports
    namespace=$(select_namespace) || return
    pod=$(select_pod "$namespace") || return

    local_port=$(seq 1024 65535 | fzf --prompt "🔌 Select a local port: ") || return
    ports=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath="{.spec.containers[*].ports[*].containerPort}" 2>/dev/null)
    remote_port=$(select_port "🎯 Select pod port: " "$ports") || return

    frame_message "$BLUE" "Forwarding pod $pod in namespace $namespace → localhost:$local_port => pod:$remote_port"
    kubectl port-forward pod/"$pod" "$local_port":"$remote_port" -n "$namespace"
}

# Port-forward vers un Service
kube_port_forward_service() {
    local namespace svc local_port remote_port ports
    namespace=$(select_namespace) || return
    svc=$(select_svc "$namespace") || return

    ports=$(kubectl get svc "$svc" -n "$namespace" -o jsonpath="{.spec.ports[*].port}" 2>/dev/null)
    remote_port=$(select_port "🎯 Select service port: " "$ports") || return
    local_port=$(seq 1024 65535 | fzf --prompt "🔌 Select a local port: ") || return

    frame_message "$BLUE" "Forwarding service $svc in namespace $namespace → localhost:$local_port => svc:$remote_port"
    kubectl port-forward service/"$svc" "$local_port":"$remote_port" -n "$namespace"
}

# Menu principal
ok_kubectl_port_forward() {
    local choice
    choice=$(echo -e "🔹 Port-forward to a Pod\n🔸 Port-forward to a Service\n❌ Quit" | fzf --prompt "🔧 Choose an option: ") || return

    case "$choice" in
        *Pod*) kube_port_forward_pod ;;
        *Service*) kube_port_forward_service ;;
        *Quit*)
            echo "Bye 👋"
            exit 0
            ;;
        *) frame_message "$RED" "❌ Invalid choice." ;;
    esac
}

###
kube_port_forward() {
    local ns resource_type resource_name local_port remote_port selected_line

    ns=$(select_namespace) || return 1

    resource_type=$(printf "pod\ndeployment\nservice" | fzf --prompt="🔘 Select resource type for port-forward > ")
    [[ -z "$resource_type" ]] && echo "❌ No resource type selected." && return 1

    if [[ "$ns" == "all" ]]; then
        selected_line=$(kubectl get "$resource_type" --all-namespaces --no-headers | fzf --prompt="📡 Select $resource_type > ")
        [[ -z "$selected_line" ]] && echo "❌ No resource selected." && return 1
        ns=$(echo "$selected_line" | awk '{print $1}')
        resource_name=$(echo "$selected_line" | awk '{print $2}')
    else
        resource_name=$(kubectl get "$resource_type" -n "$ns" --no-headers | fzf --prompt="📡 Select $resource_type > " | awk '{print $1}')
        [[ -z "$resource_name" ]] && echo "❌ No resource selected." && return 1
    fi

    # Auto-detect remote ports based on resource type
    local port_list
    case "$resource_type" in
        service)
            port_list=$(kubectl get svc "$resource_name" -n "$ns" -o jsonpath='{.spec.ports[*].port}' | tr ' ' '\n')
            ;;
        pod)
            port_list=$(kubectl get pod "$resource_name" -n "$ns" -o json | jq -r '.spec.containers[].ports[]?.containerPort')
            ;;
        deployment)
            port_list=$(kubectl get deploy "$resource_name" -n "$ns" -o json | jq -r '.spec.template.spec.containers[].ports[]?.containerPort')
            ;;
    esac

    # Fallback if no ports found
    if [[ -z "$port_list" ]]; then
        echo "⚠️  No ports detected automatically. You must enter one manually."
        read -rp "🎯 Enter remote port on $resource_type: " remote_port
    else
        remote_port=$(echo "$port_list" | sort -n | uniq | fzf --prompt="🎯 Select remote port > ")

        if [[ -z "$remote_port" ]]; then
            echo "❌ No port selected."
            return 1
        else
            echo "📌 Port $remote_port selected."
        fi
    fi

    read -rp "🔢 Enter local port: " local_port

    echo -e "\n🔄 Forwarding localhost:$local_port → $resource_type/$resource_name:$remote_port in namespace $ns"
    kubectl port-forward -n "$ns" "$resource_type/$resource_name" "$local_port:$remote_port"
}

get_node_events() {
    local node_name choice

    node_name=$(select_node_name)
    if [[ -z "$node_name" ]]; then
        echo "Node name is empty. Exiting..."
        return 1
    fi

    echo -e "${GREEN}Selected Node: $node_name${NC}\n"

    choice=$(echo -e "Current Terminal\nNew Terminal" | fzf --prompt="Choose execution mode: ")

    case "$choice" in
        "Current Terminal")
            echo -e "${GREEN}Displaying events in current terminal:${NC}\n"
            while true; do
                print_separator_with_date
                kubectl describe node "$node_name" 2>/dev/null | awk '/Events:/,/^$/'
                sleep 5
            done
            ;;
        "New Terminal")
            echo -e "${GREEN}Opening events in new terminal...${NC}\n"
            kubelynx::run_in_new_terminal "Node events: $node_name" "
                while true; do
                    echo \"----- \$(date) -----\"
                    kubectl describe node '$node_name' 2>/dev/null | awk '/Events:/,/^$/'
                    sleep 5
                done
                exec bash"
            ;;
        *)
            echo "Invalid choice. Exiting..."
            return 1
            ;;
    esac
}
# Background mode
