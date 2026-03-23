#!/bin/bash
# litellm-diagnostics — diagnose local LiteLLM proxy at localhost:4000

set -euo pipefail

PROXY_URL="http://localhost:4000"
DEFAULT_MODEL="claude-opus-4-6"
DEFAULT_LOG_LINES=50

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}▸${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
fail()  { echo -e "${RED}✗${NC} $*"; }
header(){ echo -e "\n${BOLD}$*${NC}"; }

check_deps() {
    local missing=()
    for cmd in curl jq lsof; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        fail "Missing dependencies: ${missing[*]}"
        echo "  Install with: brew install ${missing[*]}"
        exit 1
    fi
}

find_litellm_container() {
    if command -v docker &>/dev/null; then
        docker ps --filter "ancestor=ghcr.io/berriai/litellm" --format '{{.ID}}' 2>/dev/null | head -1
    fi
}

find_litellm_pid() {
    lsof -ti :4000 2>/dev/null | head -1
}

cmd_status() {
    header "LiteLLM proxy status"

    # Health check with timing
    local start_ms end_ms elapsed_ms http_code body
    start_ms=$(python3 -c 'import time; print(int(time.time()*1000))')

    if body=$(curl -s -w '\n%{http_code}' --connect-timeout 5 --max-time 10 "${PROXY_URL}/health" 2>/dev/null); then
        end_ms=$(python3 -c 'import time; print(int(time.time()*1000))')
        elapsed_ms=$((end_ms - start_ms))
        http_code=$(echo "$body" | tail -1)
        body=$(echo "$body" | sed '$d')

        if [[ "$http_code" == "200" ]]; then
            ok "Proxy is healthy (HTTP $http_code, ${elapsed_ms}ms)"
        else
            warn "Proxy responded with HTTP $http_code (${elapsed_ms}ms)"
        fi

        # Try to extract version
        local version
        version=$(echo "$body" | jq -r '.version // empty' 2>/dev/null || true)
        if [[ -n "$version" ]]; then
            info "Version: $version"
        fi
    else
        fail "Proxy is not reachable at ${PROXY_URL}"
    fi

    # Port ownership
    echo ""
    local pid
    pid=$(find_litellm_pid)
    if [[ -n "$pid" ]]; then
        local proc_info
        proc_info=$(ps -p "$pid" -o pid=,command= 2>/dev/null || echo "$pid (unknown)")
        ok "Port 4000 owned by: $proc_info"
    else
        fail "Nothing listening on port 4000"
    fi

    # Docker check
    local container_id
    container_id=$(find_litellm_container)
    if [[ -n "$container_id" ]]; then
        info "Docker container: $container_id"
    fi

    # Env vars
    echo ""
    header "Environment"
    if [[ -n "${ANTHROPIC_BASE_URL:-}" ]]; then
        ok "ANTHROPIC_BASE_URL = $ANTHROPIC_BASE_URL"
    else
        warn "ANTHROPIC_BASE_URL is not set"
    fi

    if [[ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]]; then
        local masked="${ANTHROPIC_AUTH_TOKEN:0:8}…"
        ok "ANTHROPIC_AUTH_TOKEN = ${masked}"
    else
        warn "ANTHROPIC_AUTH_TOKEN is not set"
    fi
}

cmd_models() {
    header "Available models"

    local response
    if ! response=$(curl -s --connect-timeout 5 --max-time 10 "${PROXY_URL}/v1/models" 2>/dev/null); then
        fail "Could not reach ${PROXY_URL}/v1/models"
        exit 1
    fi

    local model_count
    model_count=$(echo "$response" | jq -r '.data | length' 2>/dev/null || echo "0")

    if [[ "$model_count" == "0" ]]; then
        warn "No models found (or unexpected response format)"
        echo "$response" | jq . 2>/dev/null || echo "$response"
        exit 1
    fi

    ok "$model_count models available:"
    echo ""
    echo "$response" | jq -r '.data[].id' 2>/dev/null | sort | while read -r model; do
        echo "  • $model"
    done
}

cmd_logs() {
    local lines="$DEFAULT_LOG_LINES"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --lines)
                lines="$2"
                shift 2
                ;;
            *)
                fail "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    header "LiteLLM logs (last $lines lines)"

    # Try docker first
    local container_id
    container_id=$(find_litellm_container)
    if [[ -n "$container_id" ]]; then
        info "Tailing docker container $container_id"
        docker logs --tail "$lines" "$container_id" 2>&1
        return 0
    fi

    # Try finding the process and its log file
    local pid
    pid=$(find_litellm_pid)
    if [[ -z "$pid" ]]; then
        fail "No litellm process found on port 4000"
        exit 1
    fi

    info "LiteLLM process PID: $pid"

    # Check common log locations
    local log_locations=(
        "$HOME/.litellm/logs/litellm.log"
        "$HOME/.litellm/litellm.log"
        "/tmp/litellm.log"
        "/var/log/litellm.log"
    )

    for log_file in "${log_locations[@]}"; do
        if [[ -f "$log_file" ]]; then
            info "Found log file: $log_file"
            tail -n "$lines" "$log_file"
            return 0
        fi
    done

    # Try to find open log files via lsof
    local log_file
    log_file=$(lsof -p "$pid" 2>/dev/null | grep -E '\.(log|txt)' | awk '{print $NF}' | head -1)
    if [[ -n "$log_file" && -f "$log_file" ]]; then
        info "Found log file via lsof: $log_file"
        tail -n "$lines" "$log_file"
        return 0
    fi

    # Try /proc or stdout fd (macOS doesn't have /proc, but try anyway)
    warn "Could not find log files"
    info "Process info:"
    ps -p "$pid" -o pid=,command= 2>/dev/null || true
    echo ""
    info "Try running litellm with --log_file or checking your launch command for output redirection"
}

cmd_test() {
    local model="$DEFAULT_MODEL"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model)
                model="$2"
                shift 2
                ;;
            *)
                fail "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    header "Testing completion with model: $model"

    local payload
    payload=$(jq -n \
        --arg model "$model" \
        '{
            model: $model,
            messages: [{ role: "user", content: "Say hello in exactly 3 words." }],
            max_tokens: 32
        }')

    local start_ms end_ms elapsed_ms response http_code
    start_ms=$(python3 -c 'import time; print(int(time.time()*1000))')

    if response=$(curl -s -w '\n%{http_code}' \
        --connect-timeout 5 \
        --max-time 30 \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${ANTHROPIC_AUTH_TOKEN:-dummy}" \
        -d "$payload" \
        "${PROXY_URL}/v1/chat/completions" 2>/dev/null); then

        end_ms=$(python3 -c 'import time; print(int(time.time()*1000))')
        elapsed_ms=$((end_ms - start_ms))
        http_code=$(echo "$response" | tail -1)
        response=$(echo "$response" | sed '$d')

        if [[ "$http_code" == "200" ]]; then
            ok "Completion succeeded (HTTP $http_code, ${elapsed_ms}ms)"
            echo ""

            local content
            content=$(echo "$response" | jq -r '.choices[0].message.content // "N/A"' 2>/dev/null)
            info "Response: $content"

            local prompt_tokens completion_tokens total_tokens
            prompt_tokens=$(echo "$response" | jq -r '.usage.prompt_tokens // "?"' 2>/dev/null)
            completion_tokens=$(echo "$response" | jq -r '.usage.completion_tokens // "?"' 2>/dev/null)
            total_tokens=$(echo "$response" | jq -r '.usage.total_tokens // "?"' 2>/dev/null)
            info "Tokens: ${prompt_tokens} prompt + ${completion_tokens} completion = ${total_tokens} total"
        else
            fail "Completion failed (HTTP $http_code, ${elapsed_ms}ms)"
            echo ""
            echo "$response" | jq . 2>/dev/null || echo "$response"
            exit 1
        fi
    else
        fail "Could not reach ${PROXY_URL}/v1/chat/completions"
        exit 1
    fi
}

cmd_restart() {
    header "Restarting LiteLLM proxy"

    # Try docker first
    local container_id
    container_id=$(find_litellm_container)
    if [[ -n "$container_id" ]]; then
        info "Found docker container: $container_id"
        info "Restarting container..."
        docker restart "$container_id"
        ok "Container restarted"

        # Wait briefly and verify
        sleep 2
        if curl -s --connect-timeout 3 "${PROXY_URL}/health" &>/dev/null; then
            ok "Proxy is healthy after restart"
        else
            warn "Proxy not yet healthy — may still be starting up"
        fi
        return 0
    fi

    # Kill process
    local pid
    pid=$(find_litellm_pid)
    if [[ -z "$pid" ]]; then
        warn "No litellm process found on port 4000"
        info "Start it with your usual command, e.g.:"
        echo "  litellm --config /path/to/config.yaml --port 4000"
        return 0
    fi

    local proc_cmd
    proc_cmd=$(ps -p "$pid" -o command= 2>/dev/null || echo "unknown")
    info "Killing PID $pid: $proc_cmd"
    kill "$pid" 2>/dev/null || true

    # Wait for process to die
    local waited=0
    while kill -0 "$pid" 2>/dev/null && [[ $waited -lt 5 ]]; do
        sleep 1
        waited=$((waited + 1))
    done

    if kill -0 "$pid" 2>/dev/null; then
        warn "Process didn't exit gracefully, sending SIGKILL"
        kill -9 "$pid" 2>/dev/null || true
    fi

    ok "Process stopped"
    echo ""
    info "Restart it with your original command:"
    echo "  $proc_cmd"
}

usage() {
    echo "Usage: diag.sh <subcommand> [options]"
    echo ""
    echo "Subcommands:"
    echo "  status              Health check, port ownership, env vars"
    echo "  models              List available models"
    echo "  logs [--lines N]    Tail proxy logs (default: $DEFAULT_LOG_LINES lines)"
    echo "  test [--model M]    Send a test completion (default: $DEFAULT_MODEL)"
    echo "  restart             Stop proxy and print restart instructions"
    echo ""
    echo "Proxy URL: $PROXY_URL"
}

# Main
check_deps

case "${1:-}" in
    status)  shift; cmd_status "$@" ;;
    models)  shift; cmd_models "$@" ;;
    logs)    shift; cmd_logs "$@" ;;
    test)    shift; cmd_test "$@" ;;
    restart) shift; cmd_restart "$@" ;;
    -h|--help|help)
        usage ;;
    "")
        usage
        exit 1 ;;
    *)
        fail "Unknown subcommand: $1"
        echo ""
        usage
        exit 1 ;;
esac
