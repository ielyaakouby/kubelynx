#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
get_logs_without_error_filtering_() {
    local NAMESPACE="${1:-}"
    local POD_NAME="${2:-}"
    ensure_pod_and_namespace "$NAMESPACE" "$POD_NAME"
    local status
    status="$?"
    if [[ "$status" -eq 0 ]]; then
        check_pod_status_for_logs "$POD_NAME" "$NAMESPACE" || return 1
        kubelynx::run_in_new_terminal "Logs - $POD_NAME ($NAMESPACE)" "kubectl logs \"$POD_NAME\" -n \"$NAMESPACE\" -f 2>/dev/null; echo; read"
    else
        echo "Failed to ensure pod and namespace."
        return 1
    fi
}
get_logs_without_error_filtering() {
    local NAMESPACE="${1:-}"
    local POD_NAME="${2:-}"
    ensure_pod_and_namespace "$NAMESPACE" "$POD_NAME"
    local status=$?

    if [[ "$status" -ne 0 ]]; then
        echo "[x] Failed to ensure pod and namespace. Exiting."
        return 1
    fi

    # Check if pod is running before getting logs
    local pod_status
    pod_status=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [[ "$pod_status" != "Running" ]]; then
        frame_message "$YELLOW" "⚠️  Pod '$POD_NAME' is not in Running state (current status: ${pod_status:-Unknown})"
        frame_message "$CYAN" "💡 Use 'kubectl describe pod $POD_NAME -n $NAMESPACE' to get more details about pod issues..."
        return 1
    fi

    local log_content
    log_content=$(kubectl logs "$POD_NAME" -n "$NAMESPACE" 2>/dev/null)
    if [[ -z "$log_content" ]]; then
        echo "[x] No logs found for pod $POD_NAME in namespace $NAMESPACE."
        return 1
    fi

    local choice
    choice=$(echo -e "[1] Terminal (current window)\n[2] gnome-terminal (new window)\n[3] Open in Kate\n[4] Open in VS Code\n[5] Open in Sublime Text\n[6] Save to temporary file" \
        | fzf --prompt="[>] Choose how to view the logs: ")

    case "$choice" in
        "[1]"*) echo "$log_content" ;;
        "[2]"*) kubelynx::run_in_new_terminal "Logs - $POD_NAME - $NAMESPACE" "kubectl logs \"$POD_NAME\" -n \"$NAMESPACE\" -f; echo ''; read" ;;
        "[3]"*)
            tmpfile=$(create_temp_file "_pod-logs-${POD_NAME}-${NAMESPACE}.log")
            echo "$log_content" >"$tmpfile"
            kate "$tmpfile" &
            ;;
        "[4]"*)
            tmpfile=$(create_temp_file "_pod-logs-${POD_NAME}-${NAMESPACE}.log")
            echo "$log_content" >"$tmpfile"
            code "$tmpfile"
            ;;
        "[5]"*)
            tmpfile=$(create_temp_file "_pod-logs-${POD_NAME}-${NAMESPACE}.log")
            echo "$log_content" >"$tmpfile"
            subl "$tmpfile"
            ;;
        "[6]"*)
            tmpfile=$(create_temp_file "_pod-logs-${POD_NAME}-${NAMESPACE}.log")
            echo "$log_content" >"$tmpfile"
            echo "[✓] Logs saved in: $tmpfile"
            ;;
        *) echo "[!] No valid option selected." ;;
    esac
}

get_logs_with_error_filtering() {
    local NAMESPACE="${1:-}"
    local POD_NAME="${2:-}"
    ensure_pod_and_namespace "$NAMESPACE" "$POD_NAME" || return

    # Check if pod is running before getting logs
    check_pod_status_for_logs "$POD_NAME" "$NAMESPACE" || return 1

    local pattern
    local patterns=(
        "[1] error"
        "[2] warning"
        "[3] info"
        "[4] Combine error, warning, and info"
        "[5] Custom pattern"
    )

    local selected_pattern
    selected_pattern=$(printf "%s\n" "${patterns[@]}" | fzf --prompt="[>] Select log pattern: ")

    case "$selected_pattern" in
        "[1]"*) pattern="error|exception|failed|fatal|crash|panic" ;;
        "[2]"*) pattern="warning|warn|alert" ;;
        "[3]"*) pattern="info|information" ;;
        "[4]"*) pattern="error|exception|failed|fatal|crash|panic|warning|warn|alert|info|information" ;;
        "[5]"*) read -r -p "[?] Enter your custom pattern: " pattern ;;
        *)
            echo "[x] Invalid option selected."
            return
            ;;
    esac

    local viewer
    viewer=$(echo -e "[1] Terminal (current window)\n[2] gnome-terminal (new window)\n[3] Open in Kate\n[4] Open in VS Code\n[5] Open in Sublime Text\n[6] Save to temporary file" \
        | fzf --prompt="[>] Choose how to view the filtered logs: ")

    case "$viewer" in
        "[1]"*)
            kubectl logs "$POD_NAME" -n "$NAMESPACE" -f 2>/dev/null | grep -i -E "$pattern"
            ;;
        "[2]"*)
            kubelynx::run_in_new_terminal "Filtered Logs - $POD_NAME" \
                "kubectl logs \"$POD_NAME\" -n \"$NAMESPACE\" -f 2>/dev/null | grep -i -E \"$pattern\"; echo ''; read"
            ;;
        "[3]"*)
            tmpfile=$(create_temp_file "_pod-logs-${POD_NAME}-${NAMESPACE}-filtered.log")
            kubectl logs "$POD_NAME" -n "$NAMESPACE" 2>/dev/null | grep -i -E "$pattern" >"$tmpfile" || {
                frame_message "$YELLOW" "⚠️  Pod '$POD_NAME' is not in Running state"
                frame_message "$CYAN" "💡 Use 'kubectl describe pod $POD_NAME -n $NAMESPACE' to get more details about pod issues..."
                return 1
            }
            kate "$tmpfile" &
            ;;
        "[4]"*)
            tmpfile=$(create_temp_file "_pod-logs-${POD_NAME}-${NAMESPACE}-filtered.log")
            kubectl logs "$POD_NAME" -n "$NAMESPACE" 2>/dev/null | grep -i -E "$pattern" >"$tmpfile"
            code "$tmpfile"
            ;;
        "[5]"*)
            tmpfile=$(create_temp_file "_pod-logs-${POD_NAME}-${NAMESPACE}-filtered.log")
            kubectl logs "$POD_NAME" -n "$NAMESPACE" 2>/dev/null | grep -i -E "$pattern" >"$tmpfile"
            subl "$tmpfile"
            ;;
        "[6]"*)
            tmpfile=$(create_temp_file "_pod-logs-${POD_NAME}-${NAMESPACE}-filtered.log")
            kubectl logs "$POD_NAME" -n "$NAMESPACE" 2>/dev/null | grep -i -E "$pattern" >"$tmpfile"
            echo "[✓] Logs saved in: $tmpfile"
            ;;
        *) echo "[x] No valid option selected." ;;
    esac
}
# Follow logs option
