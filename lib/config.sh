#!/usr/bin/env bash
# Configuration System for InitOps-Server
# Centralized configuration with validation, defaults, and schema

# ============================================================================
# CONFIGURATION SCHEMA
# ============================================================================

# Configuration schema definition
# Format: CONFIG_SCHEMA[key]="type:default:validation:description"
# type: string|bool|int|port|ip|cidr|path|enum
# validation: regex pattern or enum values (comma-separated)

declare -A CONFIG_SCHEMA=(
    # VPN Configuration
    ["vpn_provider"]="enum:pangolin:pangolin,tailscale,both,none:VPN provider to use"
    ["vpn_pangolin_enabled"]="bool:true::Enable Pangolin VPN"
    ["vpn_tailscale_enabled"]="bool:false::Enable Tailscale VPN"
    
    # Ollama Configuration
    ["ollama_enabled"]="bool:true::Enable Ollama LLM server"
    ["ollama_model"]="string:auto::Model to use (auto for hardware-aware selection)"
    ["ollama_gpu"]="bool:true::Enable GPU acceleration"
    ["ollama_gpu_vendor"]="string:auto:auto,nvidia,amd,intel,none:GPU vendor override"
    
    # Docker Configuration
    ["docker_enabled"]="bool:true::Enable Docker"
    ["docker_compose_version"]="string:v2::Docker Compose version"
    
    # Nginx Configuration
    ["nginx_enabled"]="bool:true::Enable Nginx reverse proxy"
    ["nginx_domain"]="string:local::Domain name (local for self-signed)"
    ["nginx_ssl"]="enum:self-signed:self-signed,letsencrypt,none:SSL certificate type"
    ["nginx_auth_provider"]="enum:basic:basic,authelia,oidc,none:Authentication provider"
    ["nginx_auth_users"]="string:::Colon-separated user:hash pairs for basic auth"
    ["nginx_rate_limit"]="int:10::API rate limit (requests/second)"
    
    # Network Configuration
    ["network_interface"]="string:eth0::Primary network interface"
    ["network_ap_interface"]="string:wlan0::Wireless AP interface"
    ["network_ap_ssid"]="string:InitOps-AP::AP SSID"
    ["network_ap_password"]="string:InitOpsServer::AP Password (min 8 chars)"
    ["network_ap_subnet"]="cidr:10.3.141.1/24::AP subnet CIDR"
    ["network_dns_servers"]="string:1.1.1.1,1.0.0.1::Upstream DNS servers"
    
    # Service Enablement
    ["raspap_enabled"]="bool:true::Enable RaspAP wireless AP"
    ["pihole_enabled"]="bool:true::Enable Pi-hole DNS/ad-blocking"
    ["pihole_password"]="string:::Pi-hole admin password (auto-generated if empty)"
    ["n8n_enabled"]="bool:true::Enable n8n workflow automation"
    ["n8n_encryption_key"]="string:::n8n encryption key (auto-generated if empty)"
    ["samba_enabled"]="bool:true::Enable Samba file sharing"
    ["samba_workgroup"]="string:WORKGROUP::Samba workgroup name"
    ["sterling_pdf_enabled"]="bool:true::Enable Sterling PDF toolkit"
    ["cockpit_enabled"]="bool:true::Enable Cockpit system admin"
    ["grafana_enabled"]="bool:true::Enable Grafana dashboards"
    ["grafana_admin_password"]="string:::Grafana admin password (auto-generated if empty)"
    ["prometheus_enabled"]="bool:true::Enable Prometheus monitoring stack"
    
    # System Configuration
    ["timezone"]="string:UTC::System timezone"
    ["locale"]="string:en_US.UTF-8::System locale"
    ["ssh_hardening"]="bool:true::Enable SSH hardening"
    ["firewall_enabled"]="bool:true::Enable UFW firewall"
    ["fail2ban_enabled"]="bool:true::Enable fail2ban"
    ["auto_updates"]="bool:false::Enable automatic security updates"
    
    # Advanced Configuration
    ["log_level"]="enum:info:debug,info,warn,error:Log level"
    ["dry_run"]="bool:false::Dry run mode (no changes)"
    ["skip_os_check"]="bool:false::Skip OS compatibility check"
    ["reset_state"]="bool:false::Reset installation state"
    ["single_module"]="string:::Run only specific module"
)

# ============================================================================
# CONFIGURATION DEFAULTS
# ============================================================================

declare -A CONFIG_DEFAULTS=()

# Initialize defaults from schema
_config_init_defaults() {
    for key in "${!CONFIG_SCHEMA[@]}"; do
        local schema="${CONFIG_SCHEMA[$key]}"
        local type="${schema%%:*}"
        local default="${schema#*:}"
        default="${default%%:*}"
        CONFIG_DEFAULTS["$key"]="$default"
    done
}

# ============================================================================
# CONFIGURATION STATE
# ============================================================================

declare -A CONFIG=()
declare -A CONFIG_SOURCES=()  # Track where each value came from: default|file|env|cli

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

# Validate a single configuration value
config_validate_value() {
    local key="$1"
    local value="$2"
    local schema="${CONFIG_SCHEMA[$key]:-}"
    
    if [[ -z "$schema" ]]; then
        log_warn "No schema for config key: $key"
        return 0
    fi
    
    local type="${schema%%:*}"
    local rest="${schema#*:}"
    local validation="${rest#*:}"
    validation="${validation%%:*}"
    
    case "$type" in
        string)
            return 0
            ;;
        bool)
            [[ "$value" =~ ^(true|false|yes|no|1|0)$ ]]
            ;;
        int)
            [[ "$value" =~ ^[0-9]+$ ]]
            ;;
        port)
            [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -ge 1 ]] && [[ "$value" -le 65535 ]]
            ;;
        ip)
            [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
            ;;
        cidr)
            [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]
            ;;
        path)
            [[ "$value" =~ ^/.*$ ]]
            ;;
        enum)
            local IFS=','
            for valid in $validation; do
                [[ "$value" == "$valid" ]] && return 0
            done
            log_error "Invalid value for $key: '$value'. Valid options: $validation"
            return 1
            ;;
        *)
            log_warn "Unknown config type '$type' for key '$key'"
            return 0
            ;;
    esac
}

# Validate all configuration
config_validate_all() {
    local errors=0
    for key in "${!CONFIG[@]}"; do
        if ! config_validate_value "$key" "${CONFIG[$key]}"; then
            ((errors++))
        fi
    done
    return $errors
}

# ============================================================================
# CONFIGURATION LOADING
# ============================================================================

# Load defaults
config_load_defaults() {
    _config_init_defaults
    for key in "${!CONFIG_DEFAULTS[@]}"; do
        CONFIG["$key"]="${CONFIG_DEFAULTS[$key]}"
        CONFIG_SOURCES["$key"]="default"
    done
}

# Load from YAML file
config_load_file() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    
    log_info "Loading configuration from $file"
    
    # Use yq if available, otherwise fallback to simple parser
    if command -v yq &>/dev/null; then
        _config_load_yq "$file"
    else
        _config_load_simple "$file"
    fi
}

_config_load_yq() {
    local file="$1"
    local keys
    keys=$(yq eval '.. | select(tag == "!!str") | path | join(".")' "$file" 2>/dev/null | sort -u)
    
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        local value
        value=$(yq eval ".$key" "$file" 2>/dev/null)
        [[ -z "$value" || "$value" == "null" ]] && continue
        
        # Convert key format (e.g., vpn.provider -> vpn_provider)
        local flat_key
        flat_key=$(echo "$key" | tr '.' '_')
        
        if [[ -n "${CONFIG_SCHEMA[$flat_key]:-}" ]]; then
            CONFIG["$flat_key"]="$value"
            CONFIG_SOURCES["$flat_key"]="file"
        else
            log_warn "Unknown config key in file: $flat_key (from $key)"
        fi
    done <<< "$keys"
}

_config_load_simple() {
    local file="$1"
    # Simple key: value parser for flat YAML
    while IFS=':' read -r key value; do
        key=$(echo "$key" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//; s/^'"'"'//; s/'"'"'$//')
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        [[ -n "${CONFIG_SCHEMA[$key]:-}" ]] && CONFIG["$key"]="$value" && CONFIG_SOURCES["$key"]="file"
    done < <(grep -E '^[[:space:]]*[a-z_]+:' "$file" | sed 's/^[[:space:]]*//')
}

# Load from environment variables (INITOPS_ prefix)
config_load_env() {
    local prefix="INITOPS_"
    local vars
    vars=$(env | grep "^${prefix}" | cut -d= -f1) || true
    for var in $vars; do
        [[ -z "$var" ]] && continue
        local key="${var#${prefix}}"
        key="${key,,}"  # lowercase
        local value="${!var}"
        if [[ -n "${CONFIG_SCHEMA[$key]:-}" ]]; then
            CONFIG["$key"]="$value"
            CONFIG_SOURCES["$key"]="env"
        fi
    done
}

# Load from CLI args (already parsed into CONFIG)
config_load_cli() {
    # This is called after parse_args() which populates CONFIG directly
    for key in "${!CONFIG[@]}"; do
        if [[ "${CONFIG_SOURCES[$key]:-}" != "file" && "${CONFIG_SOURCES[$key]:-}" != "env" ]]; then
            CONFIG_SOURCES["$key"]="cli"
        fi
    done
}

# Generate configuration template
config_generate_template() {
    cat << 'EOF'
# InitOps-Server Configuration
# Generated with: ./initops.sh --generate-config > config.yaml
# All values are optional - defaults will be used if omitted

# VPN Configuration
vpn:
  provider: "pangolin"          # pangolin | tailscale | both | none

# Ollama Configuration
ollama:
  enabled: true
  model: "auto"                 # auto | specific model name (e.g., llama3.1:8b)
  gpu: true                     # Use GPU if available
  gpu_vendor: "auto"            # auto | nvidia | amd | intel | none

# Docker Configuration
docker:
  enabled: true
  compose_version: "v2"

# Nginx Configuration
nginx:
  enabled: true
  domain: "local"               # local | your.domain.com
  ssl: "self-signed"            # self-signed | letsencrypt | none
  auth:
    provider: "basic"           # basic | authelia | oidc | none
    users: []                   # ["user:hash", "user2:hash"]
  rate_limit: 10                # API rate limit (req/s)

# Network Configuration
network:
  interface: "eth0"             # Primary network interface
  ap_interface: "wlan0"         # Wireless AP interface
  ap_ssid: "InitOps-AP"         # AP SSID
  ap_password: "InitOpsServer"  # AP Password (min 8 chars)
  ap_subnet: "10.3.141.1/24"    # AP subnet CIDR
  dns_servers: "1.1.1.1,1.0.0.1" # Upstream DNS servers

# Service Enablement
services:
  raspap: true
  pihole: true
  pihole_password: ""           # Auto-generated if empty
  n8n: true
  n8n_encryption_key: ""        # Auto-generated if empty
  samba: true
  samba_workgroup: "WORKGROUP"
  sterling_pdf: true
  cockpit: true
  grafana: true
  grafana_admin_password: ""    # Auto-generated if empty
  prometheus: true

# System Configuration
system:
  timezone: "UTC"
  locale: "en_US.UTF-8"
  ssh_hardening: true
  firewall_enabled: true
  fail2ban_enabled: true
  auto_updates: false

# Advanced Configuration
advanced:
  log_level: "info"             # debug | info | warn | error
  dry_run: false
  skip_os_check: false
  reset_state: false
  single_module: ""             # Run only specific module
EOF
}

# Flatten nested config for backward compatibility
config_flatten() {
    local -n src="$1"
    local -n dst="$2"
    local prefix="${3:-}"
    
    for key in "${!src[@]}"; do
        local flat_key="${prefix}${key}"
        dst["$flat_key"]="${src[$key]}"
    done
}

# Merge configuration with precedence: default < file < env < cli
config_merge() {
    config_load_defaults
    config_load_file "${CONFIG_FILE:-}"
    config_load_env
    config_load_cli
    config_validate_all
}

# Export config for use in other scripts
config_export() {
    for key in "${!CONFIG[@]}"; do
        export "INITOPS_${key^^}=${CONFIG[$key]}"
    done
}

# Print configuration summary
config_print() {
    echo "=== InitOps-Server Configuration ==="
    for key in "${!CONFIG[@]}"; do
        local source="${CONFIG_SOURCES[$key]:-unknown}"
        local desc="${CONFIG_SCHEMA[$key]##*:}"
        printf "%-30s = %-20s [%s] %s\n" "$key" "${CONFIG[$key]}" "$source" "$desc"
    done | sort
    echo "===================================="
}

# Get config value with fallback
config_get() {
    local key="$1"
    local default="${2:-}"
    echo "${CONFIG[$key]:-$default}"
}

# Set config value
config_set() {
    local key="$1"
    local value="$2"
    if config_validate_value "$key" "$value"; then
        CONFIG["$key"]="$value"
        CONFIG_SOURCES["$key"]="runtime"
        return 0
    fi
    return 1
}

# Check if service is enabled
config_service_enabled() {
    local service="$1"
    local key="${service}_enabled"
    [[ "${CONFIG[$key]:-true}" == "true" ]]
}