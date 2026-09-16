#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
# ======================================
#  ok_check_node_pods.sh
#  Sophisticated Kubernetes Pods Checker
# ======================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

# Spinner frames
frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

# Messages
echot() { echo -e "${GREEN} ➔ $*${NC}"; }
echot_success() { echo -e "${GREEN} ➔ $*${NC}"; }
info() { echo -e "${BLUE}🔹 $*${NC}"; }
success() { echo -e "${GREEN}✅ $*${NC}"; }
echot_error() { echo -e "${RED} ➔ $*${NC}"; }
error() { echo -e "${RED}❌ $*${NC}"; }
warn() { echo -e "${YELLOW} $*${NC}"; }

# Spinner basic
_monitor_spinner() {
    local pid=${!:-0}
    local delay=0.1
    local i=0
    local message="$1"

    tput civis # Hide cursor

    while ps -p $pid >/dev/null 2>&1; do
        i=$(((i + 1) % ${#frames[@]}))
        printf "\r[%s] %s" "${frames[$i]}" "$message"
        sleep $delay
    done

    printf "\r[✔] %s\n" "$message"
    tput cnorm # Show cursor
}

# Fetch all running pods once
fetch_all_pods() {
    TMP_ALL_PODS=$(mktemp)
    (kubectl get pods --all-namespaces --field-selector=status.phase=Running -o wide --no-headers >"$TMP_ALL_PODS") &
    _monitor_spinner "Fetching Running pods..."

    if [[ ! -s "$TMP_ALL_PODS" ]]; then
        error "Failed to fetch pods or no running pods found."
        exit 1
    fi
}

# Select nodes
select_nodes() {
    info "Listing Kubernetes nodes..."
    local tmp_nodes=""
    tmp_nodes=$(mktemp)

    (kubectl get nodes --no-headers -o custom-columns=NAME:.metadata.name >"$tmp_nodes") &
    _monitor_spinner "Fetching nodes list..."

    if [[ ! -s "$tmp_nodes" ]]; then
        error "No nodes found or failed to fetch nodes."
        exit 1
    fi

    NODES=$(fzf --multi --prompt="Select node(s): " <"$tmp_nodes")

    if [[ -z "$NODES" ]]; then
        error "No node selected. Exiting."
        exit 1
    fi

    echot_success "Selected node(s): $NODES"
}

# Analyze pods
analyze_pods() {
    OK_FILE=$(mktemp)
    NOK_FILE=$(mktemp)
    TMP_NODE_REPORT=$(mktemp)
    global_total=0
    global_ok=0
    global_nok=0

    (
        total_nodes=$(echo "$NODES" | wc -l)
        current_node=1

        for NODE in $NODES; do
            {

                total=0
                ok=0
                nok=0

                while read namespace pod ready_field status rest; do
                    ((total++))
                    ((global_total++))

                    ready_count=$(echo "$ready_field" | cut -d'/' -f1)
                    ready_total=$(echo "$ready_field" | cut -d'/' -f2)

                    line="$(printf "%-40s %-15s %-10s" "$namespace/$pod" "$status" "$ready_field")"

                    if [[ "$status" == "Running" && "$ready_count" == "$ready_total" ]]; then
                        echo -e "✔ $line" >>"$OK_FILE"
                        ((ok++))
                        ((global_ok++))
                    else
                        echo -e "✖ $line" >>"$NOK_FILE"
                        ((nok++))
                        ((global_nok++))
                    fi
                done < <(grep -w "$NODE" "$TMP_ALL_PODS")

                echo
                echo -e "${BLUE}🔹 Total pods checked : $total${NC}"
                echot_success "Pods OK             : $ok"
                echot_error "Pods NOT Ready      : $nok"
                echo -e "${YELLOW} ===================================================${NC}"
            } >>"$TMP_NODE_REPORT"

            ((current_node++))
        done
    ) &
    _monitor_spinner "Analyzing pods on selected nodes..."

    # Affichage après spinner
    cat "$TMP_NODE_REPORT"
    rm -f "$TMP_NODE_REPORT"

}

# Display global summary
display_summary() {
    if [[ "$global_total" -eq 0 ]]; then
        return
    fi
    echo
    warn "========== Global Pod Check Summary =========="
    info "Total pods checked : $global_total"
    echot_success "Pods OK             : $global_ok"
    echot_error "Pods NOT Ready      : $global_nok"
    warn "==============================================="
    echo
}

display_details() {
    echo
    choice=$(printf "✅ Running pods\n❌ Not running pods\n📋 All pods\n" \
        | fzf --prompt="Select pod status to display: " --height=10 --border --reverse)
    echo

    case "$choice" in
        "✅ Running pods") choice="ok" ;;
        "❌ Not running pods") choice="nok" ;;
        "📋 All pods") choice="all" ;;
        *) choice="" ;;
    esac

    format_and_display() {
        local file="$1"
        local color="$2"
        local header_color="$3"
        local section="$4"
        local indent="    "
        local tmpfile=""
        tmpfile=$(mktemp)

        {
            echo -e "Pod\tState\tReady"
            awk '{
        status=$1;
        name=$2;
        state=$3;
        ready=$4;
        if (NF >= 5) {
          for (i=4; i<NF; i++) {
            state = state " " $i;
          }
          ready=$NF;
        }
        printf("%s %s\t%s\t%s\n", status, name, state, ready);
      }' "$file"
        } | column -t -s $'\t' >"$tmpfile"

        echo
        echo -e "${indent}➔ Pods ${section}"
        echo -e "${indent}──────────────────────────────────────────────────────────────────────────"

        while IFS= read -r line; do
            if [[ "$line" == Pod* ]]; then
                echo -e "${indent}${header_color}${line}${NC}"
            else
                echo -e "${indent}${color}${line}${NC}"
            fi
        done <"$tmpfile"

        cat "$tmpfile" >>"report-all.txt"
        rm -f "$tmpfile"
    }
    case "$choice" in
        ok)
            if [[ -s "$OK_FILE" ]]; then
                info "Displaying pods OK across selected nodes..."
                format_and_display "$OK_FILE" "$GREEN" "$GREEN" "OK"
            else
                echo && warn "Pods OK             : 0"
            fi
            ;;
        nok)
            if [[ -s "$NOK_FILE" ]]; then
                info "Displaying pods NOT Ready across selected nodes..."
                format_and_display "$NOK_FILE" "$RED" "$RED" "NOT READY"
            else
                echo && warn "Pods NOT Ready      : 0"
            fi
            ;;
        all)
            if [[ -s "$OK_FILE" || -s "$NOK_FILE" ]]; then
                info "Displaying all pods across selected nodes..."
                [[ -s "$OK_FILE" ]] && format_and_display "$OK_FILE" "$GREEN" "$GREEN" "OK" || warn "Pods OK             : 0"
                [[ -s "$NOK_FILE" ]] && format_and_display "$NOK_FILE" "$RED" "$RED" "NOT READY" || warn "Pods NOT Ready      : 0"
            else
                warn "No pods to display."
            fi
            ;;
        *)
            echo && warn "No valid choice. Skipping display."
            ;;
    esac
}

# Save report
save_report() {
    read -rp "Do you want to save the report to a file? (y/N): " save_choice
    if [[ "$save_choice" == "y" || "$save_choice" == "Y" ]]; then
        REPORT_FILE="report_check_node_pods_$(date +%Y%m%d_%H%M%S).txt"
        {
            echo "Pods OK:"
            cat "$OK_FILE"
            echo
            echo "Pods NOT Ready:"
            cat "$NOK_FILE"
        } >"$REPORT_FILE"
        echot_success "Report saved to: $REPORT_FILE"
        echot " cat ./$REPORT_FILE"
    fi
}

# Count pods in all nodes
count_pods_per_node() {
    echo
    warn "========== Counting pods in all nodes =========="

    TMP_NODE_COUNTS=$(mktemp)

    (
        kubectl get pods --all-namespaces --field-selector=status.phase=Running -o custom-columns=NODE:.spec.nodeName --no-headers \
            | grep -v '^$' | sort | uniq | while read node; do
            if [[ -n "$node" ]]; then
                count=$(kubectl get pods --all-namespaces --field-selector=spec.nodeName="$node",status.phase=Running --no-headers | wc -l)
                echo "$node $count" >>"$TMP_NODE_COUNTS"
            fi
        done
    ) &
    _monitor_spinner "Counting pods in all nodes..."

    if [[ ! -s "$TMP_NODE_COUNTS" ]]; then
        error "Failed to count pods or no pods running."
        exit 1
    fi

    while read node count; do
        info "Total pods checked in $node: $count"
    done <"$TMP_NODE_COUNTS"

    warn "==============================================="
    echo

    rm -f "$TMP_NODE_COUNTS"
}

main() {
    count_pods_per_node
    select_nodes
    fetch_all_pods
    analyze_pods
    display_summary
    display_details
    save_report
}

ok_check_node_pods() {
    trap cleanup EXIT
    trap 'echo -e "\n${RED}Interrupted. Exiting.${NC}"; return 1' INT
    while true; do
        main
        read -rp "Do you want to run again? (y/N): " replay
        replay=$(echo "$replay" | tr '[:upper:]' '[:lower:]') # transforme YES en yes

        if [[ "$replay" == "y" || "$replay" == "yes" ]]; then
            continue
        else
            break
        fi
    done
}

#ok_check_node_pods
