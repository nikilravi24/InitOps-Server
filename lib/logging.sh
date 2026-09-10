#!/usr/bin/env bash
# Unified Logging & Error Handling Framework for InitOps-Server
# Structured logging, error contexts, and diagnostics

# ============================================================================
# LOGGING CONFIGURATION
# ============================================================================

# Log levels: 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR, 4=FATAL
declare -A LOG_LEVELS=(
    [DEBUG]=0
    [INFO]=1
    [WARN]=2
    [ERROR]=3
    [FATAL]=4
)

declare -A LOG_COLORS=(
    [DEBUG]="${BLUE:-}"
    [INFO]="${GREEN:-}"
    [WARN]="${YELLOW:-}"
    [ERROR]="${RED:-}"
    [FATAL]="${BOLD}${RED:-}"
)

# Current log level (default: INFO)
CURRENT_LOG_LEVEL="${LOG_LEVELS[INFO]}"

# Log format: json|text|structured
LOG_FORMAT="${LOG_FORMAT:-text}"

# Log output: stderr|file|both
LOG_OUTPUT="${LOG_OUTPUT:-stderr}"

# Log file path
LOG_FILE="${LOG_FILE:-/var/log/initops.log}"

# Structured log fields
LOG_FIELDS=()

# ============================================================================
# CORE LOGGING FUNCTIONS
# ============================================================================

# Set log level
log_set_level() {
    local level="$1"
    [[ -n "${LOG_LEVELS[$level]:-}" ]] && CURRENT_LOG_LEVEL="${LOG_LEVELS[$level]}"
}

# Get current log level name
log_get_level_name() {
    for name in "${!LOG_LEVELS[@]}"; do
        [[ "${LOG_LEVELS[$name]}" -eq "$CURRENT_LOG_LEVEL" ]] && echo "$name" && return
    done
    echo "INFO"
}

# Check if level should be logged
_log_should_log() {
    local level_num="${LOG_LEVELS[$1]:-1}"
    [[ "$level_num" -ge "$CURRENT_LOG_LEVEL" ]]
}

# Format log message
_log_format() {
    local level="$1"
    local message="$2"
    local context="${3:-}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local hostname
    hostname=$(hostname -s)
    local pid=$$
    
    case "$LOG_FORMAT" in
        json)
            local json="{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"hostname\":\"$hostname\",\"pid\":$pid,\"message\":\"$message\""
            [[ -n "$context" ]] && json+=",\"context\":$context"
            json+="}"
            echo "$json"
            ;;
        structured)
            local structured="[$timestamp] [$level] [$hostname] [$pid] $message"
            [[ -n "$context" ]] && structured+=" | $context"
            echo "$structured"
            ;;
        text|*)
            local color="${LOG_COLORS[$level]:-}"
            local nc="${NC:-}"
            local prefix="[$level]"
            [[ -n "$context" ]] && prefix+=" [$context]"
            echo -e "${color}$prefix${nc} $message"
            ;;
    esac
}

# Write log to outputs
_log_write() {
    local formatted="$1"
    
    case "$LOG_OUTPUT" in
        stderr)
            echo "$formatted" >&2
            ;;
        file)
            echo "$formatted" >> "$LOG_FILE"
            ;;
        both|*)
            echo "$formatted" >&2
            echo "$formatted" >> "$LOG_FILE"
            ;;
    esac
}

# Core log function
_log() {
    local level="$1"
    shift
    local message="$*"
    local context="${LOG_CONTEXT:-}"
    
    _log_should_log "$level" || return 0
    
    local formatted
    formatted=$(_log_format "$level" "$message" "$context")
    _log_write "$formatted"
}

# Public logging functions
log_debug() { _log "DEBUG" "$@"; }
log_info()  { _log "INFO"  "$@"; }
log_warn()  { _log "WARN"  "$@"; }
log_error() { _log "ERROR" "$@"; }
log_fatal() { _log "FATAL" "$@"; exit 1; }

# Step logging (for installation steps)
log_step() {
    local current="$1"
    local total="$2"
    local message="${3:-}"
    local context="STEP $current/$total"
    _log "INFO" "$message" "$context"
}

log_success() {
    local message="$1"
    local context="SUCCESS"
    _log "INFO" "$message" "$context"
}

# ============================================================================
# CONTEXTUAL LOGGING
# ============================================================================

# Push context onto stack
log_push_context() {
    local ctx="$1"
    if [[ -z "$LOG_CONTEXT" ]]; then
        LOG_CONTEXT="$ctx"
    else
        LOG_CONTEXT="$LOG_CONTEXT > $ctx"
    fi
    LOG_CONTEXT_STACK+=("$LOG_CONTEXT")
}

# Pop context from stack
log_pop_context() {
    unset 'LOG_CONTEXT_STACK[-1]'
    if [[ ${#LOG_CONTEXT_STACK[@]} -gt 0 ]]; then
        LOG_CONTEXT="${LOG_CONTEXT_STACK[-1]}"
    else
        LOG_CONTEXT=""
    fi
}

# Run function with context
log_with_context() {
    local ctx="$1"
    shift
    log_push_context "$ctx"
    "$@"
    local ret=$?
    log_pop_context
    return $ret
}

# ============================================================================
# ERROR HANDLING
# ============================================================================

# Error context stack
declare -A ERROR_CONTEXT=()
ERROR_STACK=()

# Capture error with context
error_capture() {
    local exit_code="$1"
    local message="$2"
    local func="${FUNCNAME[1]:-unknown}"
    local file="${BASH_SOURCE[1]:-unknown}"
    local line="${BASH_LINENO[0]:-unknown}"
    
    ERROR_CONTEXT=(
        [code]="$exit_code"
        [message]="$message"
        [function]="$func"
        [file]="$file"
        [line]="$line"
        [timestamp]=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        [context]="${LOG_CONTEXT:-}"
        [stack]="${FUNCNAME[*]}"
    )
    
    ERROR_STACK+=("${ERROR_CONTEXT[*]}")
}

# Error trap handler
error_trap() {
    local exit_code=$?
    [[ $exit_code -eq 0 ]] && return 0
    
    local cmd="${BASH_COMMAND}"
    local func="${FUNCNAME[1]:-main}"
    local file="${BASH_SOURCE[1]:-unknown}"
    local line="${BASH_LINENO[0]:-unknown}"
    
    log_error "Command failed (exit $exit_code): $cmd"
    log_error "  at $func ($file:$line)"
    log_error "  context: ${LOG_CONTEXT:-none}"
    
    error_capture "$exit_code" "Command failed: $cmd"
}

# Set up error trapping
error_setup_traps() {
    set -o errtrace
    trap 'error_trap' ERR
}

# Get last error
error_get_last() {
    [[ ${#ERROR_STACK[@]} -gt 0 ]] && echo "${ERROR_STACK[-1]}" || echo ""
}

# Clear error stack
error_clear() {
    ERROR_STACK=()
}

# Run with error handling
run_with_error_handling() {
    local name="$1"
    shift
    log_push_context "$name"
    "$@"
    local ret=$?
    log_pop_context
    
    if [[ $ret -ne 0 ]]; then
        log_error "Function '$name' failed with exit code $ret"
        error_capture "$ret" "Function '$name' failed"
    fi
    return $ret
}

# ============================================================================
# DIAGNOSTICS & DEBUGGING
# ============================================================================

# Dump current state for debugging
diagnostics_dump() {
    local output="${1:-/tmp/initops-diagnostics-$(date +%s).txt}"
    
    {
        echo "=== InitOps-Server Diagnostics ==="
        echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "Hostname: $(hostname)"
        echo "User: $(whoami)"
        echo "PID: $$"
        echo "Log Level: $(log_get_level_name)"
        echo "Log Format: $LOG_FORMAT"
        echo ""
        echo "--- Environment ---"
        env | grep -E '^(INITOPS_|CONFIG_|OS_|ARCH|DRY_RUN|NON_INTERACTIVE)' | sort
        echo ""
        echo "--- Configuration ---"
        config_print 2>/dev/null || echo "Config not loaded"
        echo ""
        echo "--- Service Registry ---"
        service_list 2>/dev/null || echo "Registry not loaded"
        echo ""
        echo "--- State ---"
        [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE" || echo "No state file"
        echo ""
        echo "--- Error Stack ---"
        for err in "${ERROR_STACK[@]}"; do
            echo "$err"
        done
        echo ""
        echo "--- System Info ---"
        uname -a
        echo ""
        df -h /
        echo ""
        free -h
        echo ""
        systemctl list-units --failed --no-legend 2>/dev/null | head -20
    } > "$output"
    
    log_info "Diagnostics saved to $output"
    echo "$output"
}

# Health check all services
health_check_all() {
    local failed=0
    local passed=0
    
    log_info "Running health checks for all services..."
    
    # Disable error trap for health checks
    trap - ERR
    
    for name in "${SERVICE_INSTALL_ORDER[@]}"; do
        if service_exists "$name" && config_service_enabled "$name" 2>/dev/null; then
            log_push_context "health:$name"
            if service_health_check "$name"; then
                log_success "$name: healthy"
                passed=$((passed + 1))
            else
                log_error "$name: unhealthy"
                failed=$((failed + 1))
            fi
            log_pop_context
        fi
    done
    
    # Re-enable error trap
    error_setup_traps
    
    log_info "Health check complete: $passed passed, $failed failed"
    return $failed
}

# ============================================================================
# PROGRESS & SPINNER
# ============================================================================

# Show spinner for long-running operations
show_spinner() {
    local pid=$1
    local message="${2:-Working...}"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    echo -n "$message "
    while kill -0 "$pid" 2>/dev/null; do
        echo -n "${spin:$i:1}"
        sleep 0.1
        echo -n $'\b'
        ((i=(i+1)%10))
    done
    echo " done"
}

# Run with spinner
run_with_spinner() {
    local message="$1"
    shift
    "$@" &
    local pid=$!
    show_spinner "$pid" "$message"
    wait "$pid"
    return $?
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Initialize logging system
logging_init() {
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    
    # Set log level from config
    local level="${CONFIG[log_level]:-info}"
    log_set_level "${level^^}"
    
    # Set log format
    LOG_FORMAT="${CONFIG[log_format]:-text}"
    
    # Initialize context stack
    LOG_CONTEXT_STACK=()
    LOG_CONTEXT=""
    
    # Set up error traps
    error_setup_traps
    
    log_debug "Logging system initialized (level: $(log_get_level_name), format: $LOG_FORMAT)"
}

# ============================================================================
# EXPORT
# ============================================================================

# Export functions for subshells
export -f log_debug log_info log_warn log_error log_fatal log_step log_success
export -f log_push_context log_pop_context log_with_context
export -f error_capture error_trap error_setup_traps error_get_last error_clear
export -f run_with_error_handling diagnostics_dump health_check_all
export -f show_spinner run_with_spinner logging_init