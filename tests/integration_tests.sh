#!/usr/bin/env bash
# Integration Tests for InitOps-Server
# BATS-compatible test framework

# ============================================================================
# TEST FRAMEWORK
# ============================================================================

TEST_TEMP_DIR=""
TEST_RESULTS=()

# Setup test environment
test_setup() {
    TEST_TEMP_DIR=$(mktemp -d -t initops-test-XXXXXX)
    export DRY_RUN=true
    export NON_INTERACTIVE=true
    export SKIP_OS_CHECK=true
    export DEBUG=false
    
    # Set up script dir constants (needed by core.sh) - use absolute path
    # Use BASH_SOURCE for reliable path resolution
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    export SCRIPT_DIR="$(cd "$script_dir/.." && pwd)"
    export LIB_DIR="${SCRIPT_DIR}/lib"
    export CONFIG_DIR="${SCRIPT_DIR}/config"
    export STATE_DIR="${SCRIPT_DIR}/state"
    export STATE_FILE="${STATE_DIR}/.initops-state"
    
    # Source all libraries (from project root using absolute paths)
    source "${SCRIPT_DIR}/lib/core.sh"
    source "${SCRIPT_DIR}/lib/config.sh"
    source "${SCRIPT_DIR}/lib/services/registry.sh"
    source "${SCRIPT_DIR}/lib/logging.sh"
    source "${SCRIPT_DIR}/lib/health.sh"
    source "${SCRIPT_DIR}/lib/backup.sh"
    source "${SCRIPT_DIR}/lib/vpn.sh"
}

# Teardown test environment
test_teardown() {
    [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]] && rm -rf "$TEST_TEMP_DIR"
}

# Assert functions
assert_equal() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    [[ "$expected" == "$actual" ]] || {
        echo "ASSERTION FAILED: $message"
        echo "  Expected: $expected"
        echo "  Actual: $actual"
        return 1
    }
}

assert_not_equal() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    [[ "$expected" != "$actual" ]] || {
        echo "ASSERTION FAILED: $message"
        echo "  Expected not: $expected"
        echo "  Actual: $actual"
        return 1
    }
}

assert_true() {
    local condition="$1"
    local message="${2:-}"
    eval "$condition" || {
        echo "ASSERTION FAILED: $message"
        echo "  Condition: $condition"
        return 1
    }
}

assert_false() {
    local condition="$1"
    local message="${2:-}"
    eval "$condition" && {
        echo "ASSERTION FAILED: $message"
        echo "  Condition should be false: $condition"
        return 1
    }
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"
    [[ "$haystack" == *"$needle"* ]] || {
        echo "ASSERTION FAILED: $message"
        echo "  Haystack: $haystack"
        echo "  Needle: $needle"
        return 1
    }
}

# Run test and capture result
run_test() {
    local test_name="$1"
    shift
    echo "Running: $test_name"
    if "$@"; then
        echo "  ✓ PASS"
        TEST_RESULTS+=("$test_name:PASS")
        return 0
    else
        echo "  ✗ FAIL"
        TEST_RESULTS+=("$test_name:FAIL")
        return 1
    fi
}

# Print test summary
test_summary() {
    local passed=0
    local failed=0
    
    echo ""
    echo "=== Test Summary ==="
    for result in "${TEST_RESULTS[@]}"; do
        local name="${result%:*}"
        local status="${result#*:}"
        if [[ "$status" == "PASS" ]]; then
            echo "  ✓ $name"
            ((passed++))
        else
            echo "  ✗ $name"
            ((failed++))
        fi
    done
    echo "Total: $passed passed, $failed failed"
    return $failed
}

# ============================================================================
# CONFIGURATION TESTS
# ============================================================================

test_config_schema_exists() {
    [[ -n "${CONFIG_SCHEMA[vpn_provider]:-}" ]]
}

test_config_defaults_loaded() {
    config_load_defaults
    [[ "${CONFIG[vpn_provider]}" == "pangolin" ]]
    [[ "${CONFIG[ollama_enabled]}" == "true" ]]
}

test_config_validation_bool() {
    config_validate_value "ollama_enabled" "true"
    config_validate_value "ollama_enabled" "false"
    ! config_validate_value "ollama_enabled" "invalid"
}

test_config_validation_enum() {
    config_validate_value "vpn_provider" "pangolin"
    config_validate_value "vpn_provider" "tailscale"
    config_validate_value "vpn_provider" "both"
    config_validate_value "vpn_provider" "none"
    ! config_validate_value "vpn_provider" "invalid"
}

test_config_validation_port() {
    config_validate_value "nginx_rate_limit" "10"
    config_validate_value "nginx_rate_limit" "65535"
    ! config_validate_value "nginx_rate_limit" "0"
    ! config_validate_value "nginx_rate_limit" "65536"
    ! config_validate_value "nginx_rate_limit" "abc"
}

test_config_generate_template() {
    local output
    output=$(config_generate_template)
    assert_contains "$output" "vpn:"
    assert_contains "$output" "ollama:"
    assert_contains "$output" "nginx:"
    assert_contains "$output" "services:"
}

# ============================================================================
# REGISTRY TESTS
# ============================================================================

test_registry_service_exists() {
    service_exists "docker"
    service_exists "ollama"
    service_exists "nginx"
    ! service_exists "nonexistent"
}

test_registry_service_type() {
    [[ "$(service_get_type "docker")" == "native" ]]
    [[ "$(service_get_type "ollama")" == "docker" ]]
    [[ "$(service_get_type "nginx")" == "native" ]]
}

test_registry_service_deps() {
    local deps
    deps=$(service_get_deps "ollama")
    [[ "$deps" == "docker" ]]
    
    deps=$(service_get_deps "nginx")
    [[ -z "$deps" ]]
}

test_registry_install_order() {
    local order
    order=$(service_get_install_order "ollama" "nginx")
    # Should include docker first (dependency of ollama)
    assert_contains "$order" "docker"
    assert_contains "$order" "ollama"
    assert_contains "$order" "nginx"
}

test_registry_groups() {
    local core
    core=$(service_group_get "core")
    assert_contains "$core" "system_update"
    assert_contains "$core" "base_deps"
    assert_contains "$core" "docker"
}

# ============================================================================
# LOGGING TESTS
# ============================================================================

test_logging_levels() {
    log_set_level "DEBUG"
    [[ "$CURRENT_LOG_LEVEL" -eq 0 ]]
    
    log_set_level "ERROR"
    [[ "$CURRENT_LOG_LEVEL" -eq 3 ]]
}

test_logging_context() {
    log_push_context "test"
    [[ "$LOG_CONTEXT" == "test" ]]
    
    log_push_context "nested"
    [[ "$LOG_CONTEXT" == "test > nested" ]]
    
    log_pop_context
    [[ "$LOG_CONTEXT" == "test" ]]
    
    log_pop_context
    [[ -z "$LOG_CONTEXT" ]]
}

test_logging_format_json() {
    LOG_FORMAT="json"
    local output
    output=$(_log_format "INFO" "test message" "test-context")
    assert_contains "$output" '"level":"INFO"'
    assert_contains "$output" '"message":"test message"'
    assert_contains "$output" '"context":"test-context"'
    LOG_FORMAT="text"
}

# ============================================================================
# HEALTH CHECK TESTS
# ============================================================================

test_health_functions_exist() {
    declare -f health_docker >/dev/null
    declare -f health_ollama >/dev/null
    declare -f health_nginx >/dev/null
    declare -f health_pihole >/dev/null
    declare -f health_n8n >/dev/null
    declare -f health_grafana >/dev/null
}

test_health_get_status_json() {
    local json
    json=$(health_get_status_json "docker" "ollama")
    assert_contains "$json" '"docker"'
    assert_contains "$json" '"ollama"'
    assert_contains "$json" '"status"'
}

# ============================================================================
# BACKUP TESTS
# ============================================================================

test_backup_manifest() {
    local backup_dir="$TEST_TEMP_DIR/test-backup"
    backup_init
    mkdir -p "$backup_dir"
    backup_manifest_create "$backup_dir"
    
    [[ -f "$backup_dir/manifest.json" ]]
    local content
    content=$(cat "$backup_dir/manifest.json")
    assert_contains "$content" "timestamp"
    assert_contains "$content" "services"
}

test_backup_manifest_add() {
    local backup_dir="$TEST_TEMP_DIR/test-backup2"
    backup_init
    mkdir -p "$backup_dir"
    backup_manifest_create "$backup_dir"
    backup_manifest_add_service "$backup_dir" "test-service" "completed" '{"key":"value"}'
    
    local content
    content=$(cat "$backup_dir/manifest.json")
    assert_contains "$content" "test-service"
    assert_contains "$content" "completed"
    assert_contains "$content" "key"
}

# ============================================================================
# UTILITY TESTS
# ============================================================================

test_get_primary_ip() {
    local ip
    ip=$(get_primary_ip)
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

test_get_total_ram_gb() {
    local ram
    ram=$(get_total_ram_gb)
    [[ "$ram" =~ ^[0-9]+$ ]]
    [[ "$ram" -gt 0 ]]
}

test_has_gpu() {
    # Should not crash
    has_gpu || true
}

test_get_gpu_vendor() {
    local vendor
    vendor=$(get_gpu_vendor)
    [[ "$vendor" =~ ^(nvidia|amd|intel|none)$ ]]
}

# ============================================================================
# STATE MANAGEMENT TESTS
# ============================================================================

test_state_management() {
    local test_state="$TEST_TEMP_DIR/test-state"
    STATE_FILE="$test_state"
    
    state_init
    state_set "test_key" "test_value"
    local value
    value=$(state_get "test_key")
    assert_equal "test_value" "$value"
    
    state_mark_done "test_done"
    state_is_done "test_done"
    
    state_mark_failed "test_failed"
    state_check "test_failed" "failed"
}

# ============================================================================
# NETWORK UTILITIES TESTS
# ============================================================================

test_get_primary_interface() {
    local iface
    iface=$(get_primary_interface)
    [[ -n "$iface" ]]
}

test_is_port_in_use() {
    # Test with a port that's definitely not in use
    ! is_port_in_use 54321
}

# ============================================================================
# DOCKER UTILITIES TESTS
# ============================================================================

test_docker_compose_function() {
    # Should not crash when docker-compose not available
    docker_compose version 2>/dev/null || true
}

# ============================================================================
# MAIN TEST RUNNER
# ============================================================================

run_all_tests() {
    test_setup
    
    # Configuration tests
    run_test "config_schema_exists" test_config_schema_exists
    run_test "config_defaults_loaded" test_config_defaults_loaded
    run_test "config_validation_bool" test_config_validation_bool
    run_test "config_validation_enum" test_config_validation_enum
    run_test "config_validation_port" test_config_validation_port
    run_test "config_generate_template" test_config_generate_template
    
    # Registry tests
    run_test "registry_service_exists" test_registry_service_exists
    run_test "registry_service_type" test_registry_service_type
    run_test "registry_service_deps" test_registry_service_deps
    run_test "registry_install_order" test_registry_install_order
    run_test "registry_groups" test_registry_groups
    
    # Logging tests
    run_test "logging_levels" test_logging_levels
    run_test "logging_context" test_logging_context
    run_test "logging_format_json" test_logging_format_json
    
    # Health check tests
    run_test "health_functions_exist" test_health_functions_exist
    run_test "health_get_status_json" test_health_get_status_json
    
    # Backup tests
    run_test "backup_manifest" test_backup_manifest
    run_test "backup_manifest_add" test_backup_manifest_add
    
    # Utility tests
    run_test "get_primary_ip" test_get_primary_ip
    run_test "get_total_ram_gb" test_get_total_ram_gb
    run_test "has_gpu" test_has_gpu
    run_test "get_gpu_vendor" test_get_gpu_vendor
    
    # State tests
    run_test "state_management" test_state_management
    
    # Network tests
    run_test "get_primary_interface" test_get_primary_interface
    run_test "is_port_in_use" test_is_port_in_use
    
    # Docker tests
    run_test "docker_compose_function" test_docker_compose_function
    
    test_teardown
    test_summary
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi