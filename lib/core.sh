#!/usr/bin/env bash
# Core utilities for InitOps-Server
# Logging, state management, OS detection, common functions

# ============================================================================
# LOGGING
# ============================================================================

log_debug() {
    [[ "${DEBUG:-false}" == "true" ]] && echo -e "${BLUE}[DEBUG]${NC} $*" >&2
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_step() {
    local current="$1"
    local total="$2"
    local message="${3:-}"
    echo -e "${CYAN}[STEP ${current}/${total}]${NC} ${BOLD}${message}${NC}" >&2
}

# ============================================================================
# STATE MANAGEMENT (Idempotency)
# ============================================================================

state_init() {
    mkdir -p "$(dirname "${STATE_FILE}")"
    [[ -f "${STATE_FILE}" ]] || touch "${STATE_FILE}"
}

state_set() {
    local key="$1"
    local value="$2"
    state_init
    # Remove existing key if present
    sed -i "/^${key}=/d" "${STATE_FILE}" 2>/dev/null || true
    # Append new value
    echo "${key}=${value}" >> "${STATE_FILE}"
}

state_get() {
    local key="$1"
    local default="${2:-}"
    state_init
    grep "^${key}=" "${STATE_FILE}" 2>/dev/null | cut -d'=' -f2- | tail -1 || echo "${default}"
}

state_check() {
    local key="$1"
    local expected_value="${2:-true}"
    local current_value
    current_value=$(state_get "${key}")
    [[ "${current_value}" == "${expected_value}" ]]
}

state_is_done() {
    local key="$1"
    state_check "${key}" "done"
}

state_mark_done() {
    local key="$1"
    state_set "${key}" "done"
}

state_mark_failed() {
    local key="$1"
    state_set "${key}" "failed"
}

# ============================================================================
# OS DETECTION
# ============================================================================

detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-unknown}"
        OS_PRETTY_NAME="${PRETTY_NAME:-Unknown Linux}"
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
        OS_PRETTY_NAME="Unknown Linux"
    fi

    # Detect architecture
    ARCH=$(uname -m)
    case "${ARCH}" in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l) ARCH="armhf" ;;
    esac

    export OS_ID OS_VERSION OS_PRETTY_NAME ARCH
}

check_os_compatibility() {
    detect_os
    log_info "Detected OS: ${OS_PRETTY_NAME} (${OS_ID} ${OS_VERSION}) on ${ARCH}"

    case "${OS_ID}" in
        debian|ubuntu|raspbian|linuxmint|pop|elementary|zorin|neon|kali|parrot)
            log_success "OS is compatible (Debian-based)"
            ;;
        arch|manjaro|endeavouros|garuda|artix|cachyos)
            log_warn "Arch-based OS detected. Some features may require adaptation."
            log_warn "Use --skip-os-check to proceed anyway (e.g., for dry-run from Arch host)"
            if [[ "${SKIP_OS_CHECK}" != "true" ]]; then
                log_error "This script targets Debian-based systems. Use --skip-os-check to override."
                exit 1
            fi
            ;;
        fedora|rhel|centos|rocky|almalinux|nobara)
            log_warn "RHEL-based OS detected. This script is designed for Debian-based systems."
            if [[ "${SKIP_OS_CHECK}" != "true" ]]; then
                log_error "Use --skip-os-check to override (not recommended for production)."
                exit 1
            fi
            ;;
        *)
            log_warn "Unknown OS: ${OS_ID}. Proceeding with caution."
            if [[ "${SKIP_OS_CHECK}" != "true" ]]; then
                log_error "Use --skip-os-check to proceed on unsupported OS."
                exit 1
            fi
            ;;
    esac
}

# ============================================================================
# SYSTEM UTILITIES
# ============================================================================

update_system() {
    if state_is_done "system_update"; then
        log_info "System already updated (state tracked), skipping"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would run: apt update && apt upgrade -y"
        state_mark_done "system_update"
        return 0
    fi

    log_info "Updating package lists..."
    apt update

    log_info "Upgrading packages..."
    DEBIAN_FRONTEND=noninteractive apt upgrade -y

    state_mark_done "system_update"
}

install_base_deps() {
    if state_is_done "base_deps"; then
        log_info "Base dependencies already installed, skipping"
        return 0
    fi

    local deps=(
        curl wget git gnupg2 lsb-release ca-certificates
        software-properties-common apt-transport-https
        jq yq bash-completion
        ufw fail2ban
        htop iotop nethogs
        vim nano
    )

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would install: ${deps[*]}"
        state_mark_done "base_deps"
        return 0
    fi

    log_info "Installing base dependencies..."
    apt update
    DEBIAN_FRONTEND=noninteractive apt install -y "${deps[@]}"

    state_mark_done "base_deps"
}

get_total_ram_gb() {
    local ram_kb
    ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    echo $((ram_kb / 1024 / 1024))
}

get_cpu_cores() {
    nproc
}

has_gpu() {
    lspci | grep -iE 'vga|3d|display' | grep -qiE 'nvidia|amd|intel' && return 0 || return 1
}

get_gpu_vendor() {
    if lspci | grep -iq nvidia; then
        echo "nvidia"
    elif lspci | grep -iq amd; then
        echo "amd"
    elif lspci | grep -iq intel; then
        echo "intel"
    else
        echo "none"
    fi
}

# ============================================================================
# NETWORK UTILITIES
# ============================================================================

get_primary_interface() {
    ip route | grep default | awk '{print $5}' | head -1
}

get_primary_ip() {
    local iface
    iface=$(get_primary_interface)
    ip -4 addr show "${iface}" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1
}

is_port_in_use() {
    local port="$1"
    ss -tuln | grep -q ":${port} "
}

wait_for_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-30}"
    local count=0

    while ! nc -z "${host}" "${port}" 2>/dev/null; do
        sleep 1
        ((count++))
        if [[ ${count} -ge ${timeout} ]]; then
            log_error "Timeout waiting for ${host}:${port}"
            return 1
        fi
    done
}

# ============================================================================
# DOCKER UTILITIES
# ============================================================================

docker_compose() {
    if command -v docker-compose &>/dev/null; then
        docker-compose "$@"
    else
        docker compose "$@"
    fi
}

pull_docker_image() {
    local image="$1"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would pull: ${image}"
        return 0
    fi
    log_info "Pulling Docker image: ${image}"
    docker pull "${image}"
}

# ============================================================================
# SERVICE MANAGEMENT
# ============================================================================

enable_and_start_service() {
    local service="$1"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would enable and start: ${service}"
        return 0
    fi
    systemctl enable "${service}"
    systemctl start "${service}"
}

restart_service() {
    local service="$1"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would restart: ${service}"
        return 0
    fi
    systemctl restart "${service}"
}

# ============================================================================
# USER INPUT (Interactive mode)
# ============================================================================

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local response

    if [[ "${NON_INTERACTIVE}" == "true" ]]; then
        [[ "${default}" == "y" ]] && return 0 || return 1
    fi

    while true; do
        if [[ "${default}" == "y" ]]; then
            read -rp "$(echo -e "${CYAN}${prompt} [Y/n]: ${NC}")" response
            response=${response:-y}
        else
            read -rp "$(echo -e "${CYAN}${prompt} [y/N]: ${NC}")" response
            response=${response:-n}
        fi
        case "${response}" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

prompt_select() {
    local prompt="$1"
    shift
    local options=("$@")
    local response

    if [[ "${NON_INTERACTIVE}" == "true" ]]; then
        echo "${options[0]}"
        return 0
    fi

    echo -e "${CYAN}${prompt}${NC}"
    for i in "${!options[@]}"; do
        echo -e "  $((i+1))) ${options[i]}"
    done

    while true; do
        read -rp "$(echo -e "${CYAN}Select [1-${#options[@]}]: ${NC}")" response
        if [[ "${response}" =~ ^[0-9]+$ ]] && [[ ${response} -ge 1 ]] && [[ ${response} -le ${#options[@]} ]]; then
            echo "${options[$((response-1))]}"
            return 0
        fi
        echo "Invalid selection. Please enter a number between 1 and ${#options[@]}."
    done
}

prompt_input() {
    local prompt="$1"
    local default="${2:-}"
    local response

    if [[ "${NON_INTERACTIVE}" == "true" ]]; then
        echo "${default}"
        return 0
    fi

    if [[ -n "${default}" ]]; then
        read -rp "$(echo -e "${CYAN}${prompt} [${default}]: ${NC}")" response
        echo "${response:-${default}}"
    else
        read -rp "$(echo -e "${CYAN}${prompt}: ${NC}")" response
        echo "${response}"
    fi
}

prompt_password() {
    local prompt="$1"
    local response

    if [[ "${NON_INTERACTIVE}" == "true" ]]; then
        echo "changeme"
        return 0
    fi

    while true; do
        read -rsp "$(echo -e "${CYAN}${prompt}: ${NC}")" response
        echo
        if [[ -n "${response}" ]]; then
            echo "${response}"
            return 0
        fi
        echo "Password cannot be empty."
    done
}

# ============================================================================
# CONFIGURATION TEMPLATE
# ============================================================================

generate_default_config() {
    cat << 'EOF'
# InitOps-Server Default Configuration
vpn:
  provider: "pangolin"

ollama:
  enabled: true
  model: "auto"
  gpu_acceleration: true

services:
  raspap: true
  pihole: true
  n8n: true
  samba: true
  sterling_pdf: true
  cockpit: true
  grafana: true

nginx:
  domain: "local"
  ssl: "self-signed"
  auth:
    provider: "basic"
    users: []

network:
  interface: "eth0"
  ap_interface: "wlan0"
EOF
}

# Initialize on source
detect_os
state_init