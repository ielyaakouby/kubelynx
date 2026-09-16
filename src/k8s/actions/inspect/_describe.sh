#!/usr/bin/env bash
# Shared globals such as NAMESPACE are defined by sibling modules.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046

open_with_editor() {
    local file="$1"
    local choice

    choice=$(printf "■ Kate\n■ VSCode\n■ Gnome-terminal\n■ Gedit\n■ Vim\n■ Cat" \
        | fzf --prompt="🎨 Select output view ➜ " \
            --height=24% --border \
            --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:italic:green,border:blue,header:yellow") || {
        echo "[✗] No editor selected. Exiting."
        return 1
    }

    case "$choice" in
        *Kate)
            kate -n "$file" &>/dev/null </dev/null &
            disown
            ;;
        *VSCode)
            code -n "$file" &>/dev/null </dev/null &
            disown
            ;;
        *Gnome-terminal) kubelynx::run_in_new_terminal "kubectl describe" "cat '$file'; echo ''; read" ;;
        *Gedit)
            gedit "$file" &>/dev/null </dev/null &
            disown
            ;;
        *Vim) vim "$file" ;;
        *Cat) cat "$file" ;;
        *) echo "[✗] Invalid editor choice." ;;
    esac
}
describe_resource_generic() {
    local type="$1"
    local namespace="${2:-}"
    local name="${3:-}"

    # Skip namespace selection for node
    if [[ "$type" != "node" && -z "$namespace" ]]; then
        namespace=$(select_namespace) || return 1
    fi

    # Select resource name if not provided
    if [[ -z "$name" ]]; then
        case "$type" in
            pod) name=$(select_pod "$namespace") ;;
            svc) name=$(select_svc "$namespace") ;;
            ingress) name=$(select_ingress "$namespace") ;;
            deployment) name=$(select_deployment "$namespace") ;;
            configmap) name=$(select_configmap "$namespace") ;;
            statefulset) name=$(select_statefulset "$namespace") ;;
            daemonset) name=$(select_daemonset "$namespace") ;;
            node) name=$(select_node_name) ;;
            *)
                echo "[✗] No selector function for type '$type'."
                return 1
                ;;
        esac
    fi

    if [[ -z "$name" ]]; then
        echo "[✗] No $type selected. Aborting."
        return 1
    fi

    local tmp_file
    local file_ns="$namespace"

    # Handle node (cluster-wide)
    if [[ "$type" == "node" ]]; then
        kubectl get node "$name" &>/dev/null || {
            echo "[✗] Node '$name' not found."
            return 1
        }
        tmp_file=$(create_temp_file "_describe_${type}_${name}.txt")
        echo "[✓] Node '$name' description ready. Opening in editor..."
        kubectl describe node "$name" >"$tmp_file"
    elif [[ "$namespace" == "all" ]]; then
        file_ns=$(kubectl get "$type" --all-namespaces --field-selector metadata.name="$name" -o jsonpath='{.items[0].metadata.namespace}')

        tmp_file=$(create_temp_file "_describe_${type}_${name}_${file_ns}.txt")
        echo "[✓] $type '$name' description ready (namespace: $file_ns). Opening in editor..."
        kubectl describe "$type" "$name" -n "$file_ns" >"$tmp_file"
    else
        kubectl -n "$namespace" get "$type" "$name" &>/dev/null || {
            echo "[✗] $type '$name' not found in namespace '$namespace'."
            return 1
        }
        tmp_file=$(create_temp_file "_describe_${type}_${name}_${namespace}.txt")
        echo "[✓] $type '$name' description ready (namespace: $namespace). Opening in editor..."
        kubectl describe "$type" "$name" -n "$namespace" >"$tmp_file"
    fi

    open_with_editor "$tmp_file"
}

kubectl_describe_pod_config() { describe_resource_generic "pod" "$@"; }
kubectl_describe_service_config() { describe_resource_generic "svc" "$@"; }
kubectl_describe_ingress_config() { describe_resource_generic "ingress" "$@"; }
kubectl_describe_node_config() { describe_resource_generic "node" "$@"; }
kubectl_describe_deployment_config() { describe_resource_generic "deployment" "$@"; }
kubectl_describe_statefulset_config() { describe_resource_generic "statefulset" "$@"; }
kubectl_describe_daemonset() { describe_resource_generic "daemonset" "$@"; }
kubectl_describe_daemonset_config() { describe_resource_generic "configmap" "$@"; }

kubectl_describe_any() {
    local namespace
    namespace=$(echo -e "all\n$(kubectl get ns --no-headers | awk '{print $1}')" \
        | fzf --prompt="▶ Select a namespace (or all) ➜ " --height=40%) || {
        echo "[✗] No namespace selected."
        return 1
    }

    local resource_type
    resource_type=$(kubectl api-resources --namespaced=true --verbs=get,list -o name \
        | sort -u | fzf --prompt="▶ Select a resource type ➜ " --height=40%) || {
        echo "[✗] No resource type selected."
        return 1
    }

    local resource_name file

    if [[ "$namespace" == "all" ]]; then
        local selection
        selection=$(kubectl get "$resource_type" --all-namespaces --no-headers 2>/dev/null \
            | awk '{print $2 " (ns:" $1 ")"}' | fzf --prompt="▶ Select a $resource_type ➜ " --height=40%) || {
            echo "[✗] No resource selected."
            return 1
        }
        namespace=$(echo "$selection" | sed -E 's/.*\(ns:([^)]*)\).*/\1/')
        resource_name=$(echo "$selection" | awk '{print $1}')
    else
        resource_name=$(kubectl get "$resource_type" -n "$namespace" --no-headers 2>/dev/null \
            | awk '{print $1}' | fzf --prompt="▶ Select a $resource_type ➜ " --height=40%) || {
            echo "[✗] No resource name selected."
            return 1
        }
    fi

    file=$(create_temp_file "_describe_${resource_type}_${resource_name}_${namespace}.txt")
    echo "[✓] Describing $resource_type '$resource_name' in namespace '$namespace'..."

    kubectl describe "$resource_type" "$resource_name" -n "$namespace" >"$file" 2>/dev/null || {
        echo "[✗] Failed to describe $resource_type '$resource_name'."
        rm -f "$file"
        return 1
    }

    open_with_editor "$file"
}

# Event filtering
