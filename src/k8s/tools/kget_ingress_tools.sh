#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
select_ingress() {
    local namespace="$1"
    local ingresses
    selected_ingress=$(kubectl get ingress -n $NAMESPACE --no-headers -o custom-columns=":metadata.name" 2>/dev/null)
    #selected_ingress=$(echo "$ingresses" | fzf --prompt "📦 Select an ingress in namespace $namespace: ")
    if [[ -z "$selected_ingress" ]]; then
        frame_message "${RED}" "No ingress selected."
        exit 1
    else
        selected_ingress=$(echo "$selected_ingress" | fzf --prompt "📦 Select an ingress in namespace $namespace: ")
    fi
    echo "$selected_ingress"
}

ok_kget_ingress_info() {
    if [ "$#" -eq 2 ]; then
        if [[ $1 = "url" ]]; then
            URL="$2"
            by_url="${3:-}"
            INGRESS_NAME="$(kubectl get ingress --all-namespaces -o json 2>/dev/null | jq -r --arg HOST "$URL" '.items[] | select(.spec.rules[].host == $HOST) | .metadata.name')"
            NAMESPACE="$(kubectl get ingress --all-namespaces -o json 2>/dev/null | jq -r --arg HOST "$URL" '.items[] | select(.spec.rules[].host == $HOST) | .metadata.namespace')"
        else
            NAMESPACE="$1"
            INGRESS_NAME="$2"
            #if [[ -z "$INGRESS_NAME" ]] || [[ -z $NAMESPACE ]]; then
            #    NAMESPACE=$(select_namespace) || exit 1
            #    INGRESS_NAME=$(select_ingress $NAMESPACE) || exit 1
            #    if [[ -z $NAMESPACE || -z "$INGRESS_NAME" ]]; then
            #        echo "namespace and/or ingress name is empty. Exiting..."
            #        return 1
            #    fi
            #    frame_message_1 "${GREEN}" "[✓] Selected Namespace: $NAMESPACE"
            #    frame_message "${GREEN}" "Selected ingress $INGRESS_NAME"
            #fi
        fi

        ingress_json=$(kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" -o json 2>/dev/null)

        if [ -z "$ingress_json" ]; then
            echo "Ingress '$INGRESS_NAME' not found in namespace '$NAMESPACE'."
            exit 1
        fi
        #ports=$(echo "$ingress_json" | jq -r 'if .spec.rules[0].http.paths[0].backend.service.port.number then
        #              [.spec.rules[0].http.paths[].backend.service.port.number] | join(", ")
        #            else "N/A" end')
        ingress_json=$(kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" -o json 2>/dev/null)
        namespace=$(echo "$ingress_json" | jq -r '.metadata.namespace')
        ingress_name=$(echo "$ingress_json" | jq -r '.metadata.name')
        #host=$(echo "$ingress_json" | jq -r '.spec.rules[].host')
        host=$(echo "$ingress_json" | jq -r 'if .spec.rules then (.spec.rules[]?.host // "N/A") else "N/A" end')
        ports=$(echo "$ingress_json" | jq -r '.spec.rules[].http.paths[].backend.service.port.number')
        age=$(echo "$ingress_json" | jq -r '.metadata.creationTimestamp')
        backend_name=$(echo "$ingress_json" | jq -r '.spec.rules[].http.paths[].backend.service.name')
        backend_ports=$(echo "$ingress_json" | jq -r '.spec.rules[].http.paths[].backend.service.port.number')
        backend_type=$(echo "$ingress_json" | jq -r '.spec.rules[].http.paths[].backend | tojson' | awk -F"{" '{print $2}' | sed 's/://g' | sed 's/"//g')
        service_fqdn="$selected_service.$selected_namespace.svc.cluster.local"
        echo "Ingress details for '$ingress_name' in namespace '$namespace':"
        echo "  - Namespace: $namespace"
        echo "  - Ingress Name: $ingress_name"
        echo "  - Host: $host"
        echo "  - Ports: $ports"
        echo "  - Age: $age"
        echo "  - Backend:"
        echo "      > name: $backend_name"
        echo "      > ports: $backend_ports"
        if [[ $backend_type == ""service"" ]]; then
            service_fqdn="$backend_name.$namespace.svc.cluster.local"
            #pods_attached="$(kubectl get pods  -n monitoring --selector $(kubectl get service kube-prometheus-stack-alertmanager -n monitoring -o jsonpath='{.spec.selector}' | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")'))"
            pods_attached="$(kubectl get pods -n $namespace --selector $(kubectl get service $backend_name -n $namespace -o jsonpath='{.spec.selector}' 2>/dev/null | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")') 2>/dev/null)"

            # Echo the result to match `kubectl get pods` format
        fi

        echo "      > backend type: $backend_type ($service_fqdn)"
        echo "      > atached to pods: $backend_type ($service_fqdn)"
        echo "$pods_attached" | while read line; do
            echo "                       > $line"
        done
    elif [[ "$1" =~ ^(help|h|--help)$ ]]; then
        echo -e "Usage: \n $0 <namespace> <ingress_name> \n $0 <url> <url_name>  \n or $0 all"
        exit 1
    elif [ "$#" -eq 1 ] && [ "$1" == "all" ]; then
        ingress_json=$(kubectl get ingress --all-namespaces -o json 2>/dev/null)

        echo -e "\nIngress details:"

        # Parse and process the JSON data
        echo "$ingress_json" | jq -r '
          .items[] |
          {
            namespace: .metadata.namespace,
            ingress_name: .metadata.name,
            host: (if .spec.rules then (.spec.rules[]?.host // "N/A") else "N/A" end),
            ports: (if .spec.rules[0].http.paths[0].backend.service.port.number then
                      [.spec.rules[0].http.paths[].backend.service.port.number] | join(", ")
                    else "N/A" end),
            age: .metadata.creationTimestamp,
            backend: {
              name: .spec.rules[].http.paths[].backend.service.name,
              port: .spec.rules[].http.paths[].backend.service.port.number,
              type: (.spec.rules[].http.paths[].backend | tojson | fromjson | .service | keys_unsorted[0])
            }
          } | @json' | while IFS= read -r ingress; do

            # Extract values from the parsed JSON
            namespace=$(echo "$ingress" | jq -r '.namespace')
            ingress_name=$(echo "$ingress" | jq -r '.ingress_name')
            host=$(echo "$ingress" | jq -r '.host')
            ports=$(echo "$ingress" | jq -r '.ports')
            age=$(echo "$ingress" | jq -r '.age')

            backend_name=$(echo "$ingress" | jq -r '.backend.name')
            backend_ports=$(echo "$ingress" | jq -r '.backend.port')
            backend_type=$(echo "$ingress" | jq -r '.backend.type')

            # Construct FQDN based on backend type
            service_fqdn="$backend_name.$namespace.svc.cluster.local"
            if [[ "$backend_type" == "service" ]]; then
                service_fqdn="$backend_name.$namespace.svc.cluster.local"
            fi

            # Display ingress details
            echo "  - namespace: $namespace"
            echo "  - ingress_name: $ingress_name"
            echo "  - host: $host"
            echo "  - ports: $ports"
            echo "  - age: $age"
            echo "  - Backend:"
            echo "      > name: $backend_name"
            echo "      > ports: $backend_ports"
            echo "      > backend type: $backend_type ($service_fqdn)"
            echo ""

        done

    else
        echo -e "Usage: \n $0 <namespace> <ingress_name> \n $0 <url> <url_name>  \n or $0 all"
        exit 1
    fi

}

kget_ingress_info() {
    local namespace="$1"
    local ingress_name="$2"

    if [[ -z "$namespace" || -z "$ingress_name" ]]; then
        namespace=$(select_namespace) || return 1
        ingress_name=$(kubectl get ingress -n "$namespace" --no-headers -o custom-columns=":.metadata.name" | fzf --prompt="Select ingress: ") || return 1
    fi

    TMP_INGRESS_JSON_FILE=$(mktemp)

    check_snipp "Fetching ingress '$ingress_name' in namespace '$namespace'" \
        "kubectl get ingress \"$ingress_name\" -n \"$namespace\" -o json > \"$TMP_INGRESS_JSON_FILE\""

    ingress_json=$(<"$TMP_INGRESS_JSON_FILE")

    if [[ -z "$ingress_json" ]]; then
        echo -e "[!] Ingress not found in namespace $namespace"
        return 1
    fi

    NAME=$(jq -r '.metadata.name' <<<"$ingress_json")
    HOSTS=$(jq -r '.spec.rules[]?.host' <<<"$ingress_json")
    BACKENDS=$(jq -r '.spec.rules[]?.http.paths[]? | "- Path: \(.path // "/"), Service: \(.backend.service.name), Port: \(.backend.service.port.number // .backend.service.port.name)"' <<<"$ingress_json")
    TLS=$(jq -r '.spec.tls[]? | "- Hosts: \(.hosts | join(", ")) | Secret: \(.secretName)"' <<<"$ingress_json")
    LABELS=$(jq -r '.metadata.labels | to_entries[] | "- \(.key): \(.value)"' <<<"$ingress_json")
    ANNOTATIONS=$(jq -r '.metadata.annotations | to_entries[] | "- \(.key): \(.value)"' <<<"$ingress_json")

    local available_sections=(
        "Name"
        "Namespace"
        "Hosts"
        "Backends"
        "TLS"
        "Labels"
        "Annotations"
    )

    local selected_sections
    selected_sections=$(printf "%s
" "${available_sections[@]}" \
        | fzf --multi --prompt="Select ingress info to display: " --header="TAB to select multiple, ENTER for all")

    if [[ -z "$selected_sections" ]]; then
        selected_sections="all"
    fi

    show_section() {
        local key="$1"
        [[ "$selected_sections" == "all" || "$selected_sections" == *"$key"* ]]
    }

    echo ""
    show_section "Name" && echo "Name: $NAME"
    show_section "Namespace" && echo "Namespace: $namespace"
    show_section "Hosts" && echo -e "Hosts:
$HOSTS"
    show_section "Backends" && echo -e "Backends:
$BACKENDS"
    show_section "TLS" && echo -e "TLS Configurations:
$TLS"

    if show_section "Labels"; then
        echo -e "
Labels:"
        [[ -z "$LABELS" ]] && echo "  > None" || echo "$LABELS"
    fi

    if show_section "Annotations"; then
        echo -e "
Annotations:"
        [[ -z "$ANNOTATIONS" ]] && echo "  > None" || echo "$ANNOTATIONS"
    fi

    echo -e "
[✓] Ingress information retrieval completed."

    rm -f "$TMP_INGRESS_JSON_FILE"
}

function kget_ingress() {
    # Check if a pattern was passed as a parameter, otherwise ask the user
    if [ -z "$1" ]; then
        # If no pattern is passed, prompt the user for input
        read -p "Enter the pattern to search (or press Enter to show all): " pattern
    else
        # Use the passed pattern
        pattern=$1
    fi

    # Display all Ingress if no pattern is entered
    if [ -z "$pattern" ]; then
        kubectl get ingress -A | awk '{print $1" "$2" "$3" "$4}' | column -t
    else
        kubectl get ingress -A | awk '{print $1" "$2" "$3" "$4}' | column -t | grep "$pattern"
    fi
}
