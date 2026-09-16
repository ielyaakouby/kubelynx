#!/usr/bin/env bash
# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
# AI analysis is optional. API keys stay in the environment/headers and are
# never added to prompts, logs, or diagnostic temp files.

# Disable xtrace around curl so API keys cannot leak via `bash -x`.
kubelynx::curl_silent() {
    set +x
    curl "$@"
}

# Helper to check if Ollama is reachable
is_ollama_reachable() {
    local host="${OLLAMA_HOST:-http://localhost:11434}"
    if ! command -v curl >/dev/null 2>&1; then
        return 1
    fi
    if kubelynx::curl_silent -s --connect-timeout 2 "$host" >/dev/null; then
        return 0
    fi
    return 1
}

# Helper to call Ollama
call_ollama() {
    local prompt="$1"
    local host="${OLLAMA_HOST:-http://localhost:11434}"
    local model="${OLLAMA_MODEL:-llama3.1}"
    local json_payload response

    json_payload="$(jq -n \
        --arg model "$model" \
        --arg prompt "$prompt" \
        '{model: $model, prompt: $prompt, stream: false}')"

    if ! response="$(kubelynx::curl_silent -sS --connect-timeout 10 -X POST "$host/api/generate" \
        -H "Content-Type: application/json" \
        -d "$json_payload")"; then
        echo "Ollama request failed (is $host reachable?)" >&2
        return 1
    fi

    printf '%s\n' "$response" | jq -r '.response // empty'
}

# Helper to call Gemini
# The API key is sent as a header, not a URL query parameter, and is never printed.
call_gemini() {
    local prompt="$1"
    local api_key="$2"
    local model="${GEMINI_MODEL:-gemini-2.5-flash}"
    local url="https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent"
    local json_payload response error_msg

    json_payload="$(jq -n \
        --arg text "$prompt" \
        '{contents: [{parts: [{text: $text}]}]}')"

    if ! response="$(kubelynx::curl_silent -sS --connect-timeout 20 -X POST "$url" \
        -H "Content-Type: application/json" \
        -H "x-goog-api-key: ${api_key}" \
        -d "$json_payload")"; then
        echo "Gemini request failed" >&2
        return 1
    fi

    error_msg="$(printf '%s\n' "$response" | jq -r '.error.message // empty')"
    if [[ -n "$error_msg" ]]; then
        echo "GEMINI_ERROR:${error_msg}" >&2
        return 1
    fi

    printf '%s\n' "$response" | jq -r '.candidates[0].content.parts[0].text // empty'
}

# Helper to call OpenAI
call_openai() {
    local prompt="$1"
    local api_key="$2"
    local model="${OPENAI_MODEL:-gpt-4o-mini}"
    local url="https://api.openai.com/v1/chat/completions"
    local system_msg json_payload response

    system_msg="You are an expert Kubernetes Site Reliability Engineer called KubeLynx AI. Analyze the provided pod logs and events to diagnose the issue. Produce a beautifully formatted terminal report using ANSI escape codes and box-drawing characters."

    json_payload="$(jq -n \
        --arg model "$model" \
        --arg sys "$system_msg" \
        --arg user "$prompt" \
        '{model: $model, messages: [{role: "system", content: $sys}, {role: "user", content: $user}]}')"

    if ! response="$(kubelynx::curl_silent -sS --connect-timeout 20 -X POST "$url" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${api_key}" \
        -d "$json_payload")"; then
        echo "OpenAI request failed" >&2
        return 1
    fi

    printf '%s\n' "$response" | jq -r '.choices[0].message.content // empty'
}

ai_analysis::analyze_pod() {
    local namespace="${1:-}"
    local pod_name="${2:-}"

    if [[ -z "$namespace" ]]; then
        namespace=$(select_namespace) || return 1
    fi

    if [[ -z "$pod_name" ]]; then
        pod_name=$(select_pod "$namespace") || return 1
    fi

    # Check pod status first
    local pod_status
    pod_status=$(kubectl get pod "$pod_name" -n "$namespace" --no-headers | awk '{print $3}')

    if [[ "$pod_status" == "Running" || "$pod_status" == "Completed" || "$pod_status" == "Succeeded" ]]; then
        echo -e "\n${YELLOW}[WARN]  Pod '$pod_name' is in '$pod_status' state — no issues detected, skipping AI analysis.${NC}"
        return 0
    fi

    echo -e "\n${BLUE}[INFO]  Gathering details for pod $namespace/$pod_name...${NC}"

    # Gather context
    local logs_output
    logs_output=$(kubectl logs "$pod_name" -n "$namespace" --tail=50 2>/dev/null)
    if [[ -z "$logs_output" ]]; then
        logs_output="No logs found or unable to retrieve logs."
    fi

    local events_output
    events_output=$(kubectl get events -n "$namespace" --field-selector involvedObject.name="$pod_name" --sort-by='.lastTimestamp' -o custom-columns=TYPE:.type,REASON:.reason,MESSAGE:.message --no-headers 2>/dev/null)
    if [[ -z "$events_output" ]]; then
        events_output="No events found."
    fi

    # Prepare Prompt — instructs the AI to produce a styled terminal report
    local prompt
    prompt=$(
        cat <<EOF
You are "KubeLynx AI", a friendly and expert Kubernetes SRE assistant.
Analyze the unhealthy pod below and produce a BEAUTIFULLY FORMATTED terminal diagnostic report.

STRICT FORMATTING RULES — follow ALL of these:

1. USE ANSI escape codes for colors:
   - Bold Cyan    : \\033[1;36m  (for box borders and headers)
   - Bold Red     : \\033[1;31m  (for root cause)
   - Bold Yellow  : \\033[1;33m  (for impact)
   - Bold Green   : \\033[1;32m  (for fix steps and tips)
   - Bold Blue    : \\033[1;34m  (for verification)
   - Bold Magenta : \\033[1;35m  (for key values like pod name)
   - Dim White    : \\033[0;37m  (for commands)
   - Reset        : \\033[0m

2. NEVER use Markdown formatting (no asterisks, no hashes, no code fences, no dashes as bullets).
3. USE emoji prefixes for sections.
4. USE unicode box-drawing: ┌ ┐ └ ┘ │ ├ ┤ ─
5. Keep total output between 20-30 lines.
6. Include EXACT kubectl commands user can copy-paste.
7. Be friendly, encouraging. End with a helpful tip.
8. Each line inside the box MUST start with \\033[1;36m│\\033[0m

PRODUCE YOUR RESPONSE IN EXACTLY THIS STRUCTURE:

\\033[1;36m┌──────────────────────────────────────────────────────────────────┐\\033[0m
\\033[1;36m│\\033[0m  \\033[1;36m🔬 KubeLynx AI — Diagnostic Report\\033[0m
\\033[1;36m├──────────────────────────────────────────────────────────────────┤\\033[0m
\\033[1;36m│\\033[0m  📦 Pod:       \\033[1;35m<pod_name>\\033[0m
\\033[1;36m│\\033[0m  📍 Namespace: \\033[1;35m<namespace>\\033[0m
\\033[1;36m│\\033[0m  🔴 Status:    \\033[1;31m<status>\\033[0m
\\033[1;36m├──────────────────────────────────────────────────────────────────┤\\033[0m
\\033[1;36m│\\033[0m
\\033[1;36m│\\033[0m  \\033[1;31m🔍 Root Cause\\033[0m
\\033[1;36m│\\033[0m    <1-2 sentences explaining what went wrong and WHY>
\\033[1;36m│\\033[0m
\\033[1;36m│\\033[0m  \\033[1;33m⚡ Impact\\033[0m
\\033[1;36m│\\033[0m    <1 sentence about the consequence>
\\033[1;36m│\\033[0m
\\033[1;36m│\\033[0m  \\033[1;32m🛠️  Fix\\033[0m
\\033[1;36m│\\033[0m    1. <brief description of step>
\\033[1;36m│\\033[0m       \\033[0;37m\\$ kubectl <exact command>\\033[0m
\\033[1;36m│\\033[0m    2. <brief description of step>
\\033[1;36m│\\033[0m       \\033[0;37m\\$ kubectl <exact command>\\033[0m
\\033[1;36m│\\033[0m
\\033[1;36m│\\033[0m  \\033[1;34m✅ Verify\\033[0m
\\033[1;36m│\\033[0m    \\033[0;37m\\$ kubectl get pod <pod> -n <ns> -w\\033[0m
\\033[1;36m│\\033[0m    \\033[0;37m\\$ kubectl logs <pod> -n <ns> --tail=10\\033[0m
\\033[1;36m│\\033[0m
\\033[1;36m└──────────────────────────────────────────────────────────────────┘\\033[0m
\\033[1;32m💡 Pro Tip:\\033[0m <a helpful, actionable tip related to preventing this issue>

POD DATA TO ANALYZE:

Pod Name:  $pod_name
Namespace: $namespace
Status:    $pod_status

--- LOGS (last 50 lines) ---
$logs_output

--- EVENTS ---
$events_output
EOF
    )

    local analysis=""
    local ai_error=""

    # Determine AI Engine (priority: Gemini > Ollama > OpenAI)
    # API keys are never interpolated into the prompt.
    if [[ -n "${GEMINI_API_KEY:-}" ]]; then
        local gemini_model="${GEMINI_MODEL:-gemini-2.5-flash}"
        echo -e "${BLUE}🤖 [INFO]  Analysis in progress (Gemini: $gemini_model)...${NC}"
        ai_error="$(create_temp_file "_ai-error")"
        analysis="$(call_gemini "$prompt" "${GEMINI_API_KEY}" 2>"$ai_error")" || true
        if [[ -s "$ai_error" ]]; then
            local err_detail
            err_detail="$(sed 's/^GEMINI_ERROR://' "$ai_error")"
            echo -e "\n${RED}❌ [ERROR] Gemini API error: $err_detail${NC}"
            rm -f "$ai_error"
            return 1
        fi
        rm -f "$ai_error"
    elif is_ollama_reachable; then
        echo -e "${BLUE}🤖 [INFO]  Analysis in progress (Ollama)...${NC}"
        analysis="$(call_ollama "$prompt")" || true
    elif [[ -n "${OPENAI_API_KEY:-}" ]]; then
        echo -e "${BLUE}🤖 [INFO]  Analysis in progress (OpenAI)...${NC}"
        analysis="$(call_openai "$prompt" "${OPENAI_API_KEY}")" || true
    else
        echo -e "\n${RED}❌ [ERROR] No AI engine available.${NC}"
        echo -e "${YELLOW}Please configure one of the following:${NC}"
        echo -e "  ${GREEN}export GEMINI_API_KEY=\"...\"${NC}   (recommended)"
        echo -e "  ${GREEN}export OPENAI_API_KEY=\"...\"${NC}"
        echo -e "  Or start Ollama: ${GREEN}ollama serve${NC}\n"
        return 1
    fi

    if [[ -z "$analysis" ]]; then
        echo -e "\n${RED}❌ [ERROR] AI Analysis failed or returned empty response.${NC}"
    else
        echo ""
        echo -e "$analysis"
        echo ""
    fi

}

# Model selection
