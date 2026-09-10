#!/usr/bin/env bash
# Service Registry for InitOps-Server
# Centralized service definitions, dependencies, and lifecycle management

# ============================================================================
# SERVICE REGISTRY
# ============================================================================

# Service definition structure:
# SERVICES[name]="type:install_func:health_func:backup_func:restore_func:deps:ports:description"
# type: native|docker|compose
# deps: comma-separated service names that must be installed first
# ports: comma-separated ports the service exposes

declare -A SERVICES=(
    # Core infrastructure
    ["system_update"]="native:update_system:health_system_update::::System package updates"
    ["base_deps"]="native:install_base_deps:health_base_deps::::Base dependencies"
    ["docker"]="native:install_docker:health_docker:::2375,2376:Docker Engine"
    
    # VPN Services
    ["vpn_pangolin"]="native:install_pangolin:health_pangolin:::51820:Pangolin VPN"
    ["vpn_tailscale"]="native:install_tailscale:health_tailscale:::41641:Tailscale VPN"
    
    # Core Platform Services
    ["ollama"]="docker:install_ollama:health_ollama:backup_ollama:restore_ollama:docker:11434:Ollama LLM Server"
    ["nginx"]="native:setup_nginx:health_nginx:::80,443:Nginx Reverse Proxy"
    
    # Application Services
    ["raspap"]="native:install_raspap:health_raspap:::80,53,67:RaspAP Wireless AP"
    ["pihole"]="docker:install_pihole:health_pihole:backup_pihole:restore_pihole:docker:53,8080,443:Pi-hole DNS/Ad-blocking"
    ["n8n"]="docker:install_n8n:health_n8n:backup_n8n:restore_n8n:docker:5678:n8n Workflow Automation"
    ["samba"]="native:install_samba:health_samba:backup_samba:restore_samba:::139,445:Samba File Sharing"
    ["sterling_pdf"]="docker:install_sterling_pdf:health_sterling_pdf:::3001:Sterling PDF Toolkit"
    ["cockpit"]="native:install_cockpit:health_cockpit:::9090:Cockpit System Admin"
    ["grafana"]="docker:install_grafana:health_grafana:backup_grafana:restore_grafana:docker:3000:Grafana Dashboards"
    ["prometheus_stack"]="docker:install_prometheus_stack:health_prometheus_stack:::9090,9100,8080,9093:Prometheus Monitoring Stack"
)

# Service groups for bulk operations
declare -A SERVICE_GROUPS=(
    ["core"]="system_update base_deps docker nginx"
    ["vpn"]="vpn_pangolin vpn_tailscale"
    ["ai"]="ollama"
    ["network"]="raspap pihole samba"
    ["automation"]="n8n"
    ["monitoring"]="grafana prometheus_stack cockpit"
    ["productivity"]="sterling_pdf"
    ["all"]="system_update base_deps docker vpn_pangolin vpn_tailscale ollama nginx raspap pihole n8n samba sterling_pdf cockpit grafana prometheus_stack"
)

# Service installation order (respects dependencies)
SERVICE_INSTALL_ORDER=(
    "system_update"
    "base_deps"
    "docker"
    "vpn_pangolin"
    "vpn_tailscale"
    "ollama"
    "nginx"
    "raspap"
    "pihole"
    "n8n"
    "samba"
    "sterling_pdf"
    "cockpit"
    "grafana"
    "prometheus_stack"
)

# ============================================================================
# REGISTRY FUNCTIONS
# ============================================================================

# Get service definition
service_get_def() {
    local name="$1"
    echo "${SERVICES[$name]:-}"
}

# Check if service exists
service_exists() {
    local name="$1"
    [[ -n "${SERVICES[$name]:-}" ]]
}

# Get service type (native|docker|compose)
service_get_type() {
    local name="$1"
    local def
    def=$(service_get_def "$name")
    echo "${def%%:*}"
}

# Get service install function
service_get_install_func() {
    local name="$1"
    local def
    def=$(service_get_def "$name")
    echo "${def#*:}" | cut -d: -f1
}

# Get service health check function
service_get_health_func() {
    local name="$1"
    local def
    def=$(service_get_def "$name")
    echo "${def#*:}" | cut -d: -f2
}

# Get service backup function
service_get_backup_func() {
    local name="$1"
    local def
    def=$(service_get_def "$name")
    echo "${def#*:}" | cut -d: -f3
}

# Get service restore function
service_get_restore_func() {
    local name="$1"
    local def
    def=$(service_get_def "$name")
    echo "${def#*:}" | cut -d: -f4
}

# Get service dependencies
service_get_deps() {
    local name="$1"
    local def
    def=$(service_get_def "$name")
    local deps_field
    deps_field=$(echo "${def#*:}" | cut -d: -f5)
    echo "${deps_field//,/ }"
}

# Get service ports
service_get_ports() {
    local name="$1"
    local def
    def=$(service_get_def "$name")
    local ports_field
    ports_field=$(echo "${def#*:}" | cut -d: -f6)
    echo "${ports_field//,/ }"
}

# Get service description
service_get_description() {
    local name="$1"
    local def
    def=$(service_get_def "$name")
    echo "${def#*:}" | cut -d: -f7-
}

# Get services in a group
service_group_get() {
    local group="$1"
    echo "${SERVICE_GROUPS[$group]:-}"
}

# List all services
service_list() {
    for name in "${SERVICE_INSTALL_ORDER[@]}"; do
        if service_exists "$name"; then
            local desc
            desc=$(service_get_description "$name")
            echo "$name: $desc"
        fi
    done
}

# List enabled services from config
service_list_enabled() {
    local config_prefix="${1:-CONFIG}"
    for name in "${SERVICE_INSTALL_ORDER[@]}"; do
        if service_exists "$name"; then
            local enabled_var="${name//-/_}_enabled"
            enabled_var="${enabled_var^^}"
            if [[ "${!config_prefix[$enabled_var]:-true}" == "true" ]]; then
                local desc
                desc=$(service_get_description "$name")
                echo "$name: $desc"
            fi
        fi
    done
}

# Validate service dependencies
service_validate_deps() {
    local name="$1"
    local deps
    deps=$(service_get_deps "$name")
    
    for dep in $deps; do
        if ! service_exists "$dep"; then
            log_error "Service '$name' depends on unknown service '$dep'"
            return 1
        fi
    done
    return 0
}

# Get installation order with dependencies resolved
service_get_install_order() {
    local services=("$@")
    local ordered=()
    local processed=()
    
    # Add dependencies first
    for svc in "${services[@]}"; do
        _service_add_with_deps "$svc" ordered processed
    done
    
    echo "${ordered[@]}"
}

_service_add_with_deps() {
    local svc="$1"
    local -n ordered_ref="$2"
    local -n processed_ref="$3"
    
    # Already processed
    for p in "${processed_ref[@]}"; do
        [[ "$p" == "$svc" ]] && return 0
    done
    
    # Process dependencies first
    local deps
    deps=$(service_get_deps "$svc")
    for dep in $deps; do
        _service_add_with_deps "$dep" ordered_ref processed_ref
    done
    
    # Add this service
    ordered_ref+=("$svc")
    processed_ref+=("$svc")
}

# Get health check function for a service
service_health_check() {
    local name="$1"
    local func
    func=$(service_get_health_func "$name")
    if [[ -n "$func" && "$func" != "" ]]; then
        if declare -f "$func" >/dev/null; then
            "$func" "$name"
            return $?
        else
            log_warn "Health check function '$func' not found for service '$name'"
            return 1
        fi
    fi
    # Default: check if state is done
    state_is_done "$name"
}

# Execute backup for a service
service_backup() {
    local name="$1"
    local func
    func=$(service_get_backup_func "$name")
    if [[ -n "$func" && "$func" != "" ]]; then
        if declare -f "$func" >/dev/null; then
            "$func"
            return $?
        else
            log_warn "Backup function '$func' not found for service '$name'"
            return 1
        fi
    fi
    log_info "No backup function for service '$name'"
    return 0
}

# Execute restore for a service
service_restore() {
    local name="$1"
    local func
    func=$(service_get_restore_func "$name")
    if [[ -n "$func" && "$func" != "" ]]; then
        if declare -f "$func" >/dev/null; then
            "$func"
            return $?
        else
            log_warn "Restore function '$func' not found for service '$name'"
            return 1
        fi
    fi
    log_info "No restore function for service '$name'"
    return 0
}