#!/usr/bin/env bash
# InitOps-Server - Multi-purpose utility server setup script for Linux
# Main entry point - RESTRUCTURED VERSION

set -euo pipefail

# ============================================================================
# GLOBALS & CONSTANTS
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/lib"
readonly CONFIG_DIR="${SCRIPT_DIR}/config"
readonly STATE_DIR="${SCRIPT_DIR}/state"
readonly STATE_FILE="${STATE_DIR}/.initops-state"

readonly VERSION="1.0.0-alpha"
readonly PROJECT_NAME="InitOps-Server"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# ============================================================================
# SOURCE LIBRARIES (NEW MODULAR SYSTEM)
# ============================================================================

# Core libraries (load first)
source "${LIB_DIR}/core.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/services/registry.sh"
source "${LIB_DIR}/health.sh"
source "${LIB_DIR}/backup.sh"
source "${LIB_DIR}/dashboard.sh"

# Service modules
source "${LIB_DIR}/vpn.sh"
source "${LIB_DIR}/docker.sh"
source "${LIB_DIR}/ollama.sh"
source "${LIB_DIR}/nginx.sh"
source "${LIB_DIR}/services/raspap.sh"
source "${LIB_DIR}/services/pihole.sh"
source "${LIB_DIR}/services/n8n.sh"
source "${LIB_DIR}/services/samba.sh"
source "${LIB_DIR}/services/sterling-pdf.sh"
source "${LIB_DIR}/services/cockpit.sh"
source "${LIB_DIR}/services/grafana.sh"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

print_banner() {
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
    ██╗███╗   ██╗███████╗██╗  ██╗████████╗██████╗  █████╗  ██████╗ ███████╗██████╗ 
    ██║████╗  ██║██╔════╝██║  ██║╚══██╔══╝██╔══██╗██╔══██╗██╔═══██╗██╔════╝██╔══██╗
    ██║██╔██╗ ██║█████╗  ███████║   ██║   ██████╔╝███████║██║   ██║█████╗  ██████╔╝
    ██║██║╚██╗██║██╔══╝  ██╔══██║   ██║   ██╔══██╗██╔══██║██║   ██║██╔══╝  ██╔══██╗
    ██║██║ ╚████║███████╗██║  ██║   ██║   ██║  ██║██║  ██║╚██████╔╝███████╗██║  ██║
    ╚═╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝
EOF
    echo -e "${NC}"
    echo -e "${BOLD}${PROJECT_NAME} v${VERSION}${NC} — Multi-purpose utility server setup for Linux"
    echo
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help                  Show this help message
    -v, --version               Show version
    -c, --config FILE           Use configuration file (YAML)
    -n, --non-interactive       Run in non-interactive mode (requires --config)
    -t, --target USER@HOST      Remote target for deployment
    --generate-config           Generate example configuration file
    --skip-os-check             Skip OS compatibility check (for dry-run from non-Debian)
    --dry-run                   Show what would be done without executing
    --reset-state               Reset installation state (use with caution)
    --module MODULE             Run only specific module
    --list-modules              List all available modules
    --health-check              Run health checks on all services
    --backup-full               Create full system backup
    --backup-list               List available backups
    --backup-clean              Clean old backups
    --dashboard-install         Install web dashboard
    --dashboard-start           Start dashboard server
    --discover                  Generate service discovery JSON

EXAMPLES:
    # Interactive setup (recommended for first run)
    sudo ./initops.sh

    # Non-interactive with config file
    ./initops.sh --generate-config > config.yaml
    # Edit config.yaml, then:
    sudo ./initops.sh --config config.yaml --non-interactive

    # Remote deployment
    sudo ./initops.sh --target user@192.168.1.100

    # Dry run from non-Debian host (e.g., Arch Linux)
    ./initops.sh --skip-os-check --dry-run --config config.yaml

    # Run only VPN module
    sudo ./initops.sh --module vpn

    # Health check all services
    sudo ./initops.sh --health-check

    # Full backup
    sudo ./initops.sh --backup-full

    # Install and start dashboard
    sudo ./initops.sh --dashboard-install
    sudo ./initops.sh --dashboard-start

    # Generate service discovery for external tools
    sudo ./initops.sh --discover

EOF
}

# ============================================================================
# CONFIGURATION HANDLING (ENHANCED)
# ============================================================================

declare -A CONFIG=()

parse_args() {
    local non_interactive=false
    local generate_config=false
    local skip_os_check=false
    local dry_run=false
    local reset_state=false
    local target=""
    local config_file=""
    local single_module=""
    local list_modules=false
    local health_check=false
    local backup_full=false
    local backup_list=false
    local backup_clean=false
    local dashboard_install=false
    local dashboard_start=false
    local discover=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                print_usage
                exit 0
                ;;
            -v|--version)
                echo "${PROJECT_NAME} v${VERSION}"
                exit 0
                ;;
            -c|--config)
                config_file="$2"
                shift 2
                ;;
            -n|--non-interactive)
                non_interactive=true
                shift
                ;;
            -t|--target)
                target="$2"
                shift 2
                ;;
            --generate-config)
                generate_config=true
                shift
                ;;
            --skip-os-check)
                skip_os_check=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --reset-state)
                reset_state=true
                shift
                ;;
            --module)
                single_module="$2"
                shift 2
                ;;
            --list-modules)
                list_modules=true
                shift
                ;;
            --health-check)
                health_check=true
                shift
                ;;
            --backup-full)
                backup_full=true
                shift
                ;;
            --backup-list)
                backup_list=true
                shift
                ;;
            --backup-clean)
                backup_clean=true
                shift
                ;;
            --dashboard-install)
                dashboard_install=true
                shift
                ;;
            --dashboard-start)
                dashboard_start=true
                shift
                ;;
            --discover)
                discover=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    # Export for use in other functions
    export NON_INTERACTIVE="${non_interactive}"
    export GENERATE_CONFIG="${generate_config}"
    export SKIP_OS_CHECK="${skip_os_check}"
    export DRY_RUN="${dry_run}"
    export RESET_STATE="${reset_state}"
    export TARGET="${target}"
    export CONFIG_FILE="${config_file}"
    export SINGLE_MODULE="${single_module}"
    export LIST_MODULES="${list_modules}"
    export HEALTH_CHECK="${health_check}"
    export BACKUP_FULL="${backup_full}"
    export BACKUP_LIST="${backup_list}"
    export BACKUP_CLEAN="${backup_clean}"
    export DASHBOARD_INSTALL="${dashboard_install}"
    export DASHBOARD_START="${dashboard_start}"
    export DISCOVER="${discover}"
}

load_config_file() {
    if [[ -n "${CONFIG_FILE}" && -f "${CONFIG_FILE}" ]]; then
        log_info "Loading configuration from ${CONFIG_FILE}"
        config_load_file "${CONFIG_FILE}"
    fi
}

generate_config_template() {
    config_generate_template
}

# ============================================================================
# MODULE EXECUTION
# ============================================================================

run_module() {
    local module="$1"
    log_info "Running module: ${module}"
    
    case "${module}" in
        vpn)
            install_vpn "${CONFIG[vpn_provider]:-pangolin}"
            ;;
        docker)
            install_docker
            ;;
        ollama)
            install_ollama "${CONFIG[ollama_model]:-auto}" "${CONFIG[ollama_gpu]:-true}"
            ;;
        nginx)
            setup_nginx
            ;;
        raspap)
            install_raspap "${CONFIG[network_interface]:-eth0}" "${CONFIG[ap_interface]:-wlan0}"
            ;;
        pihole)
            install_pihole
            ;;
        n8n)
            install_n8n
            ;;
        samba)
            install_samba
            ;;
        sterling-pdf)
            install_sterling_pdf
            ;;
        cockpit)
            install_cockpit
            ;;
        grafana)
            install_grafana
            ;;
        prometheus)
            install_prometheus_stack
            ;;
        dashboard)
            dashboard_install
            ;;
        *)
            log_error "Unknown module: ${module}"
            log_info "Available modules: $(service_list | cut -d: -f1 | tr '\n' ' ')"
            return 1
            ;;
    esac
}

run_full_installation() {
    log_info "Starting full installation..."
    
    # Get enabled services in dependency order
    local enabled_services=()
    for svc in "${SERVICE_INSTALL_ORDER[@]}"; do
        if config_service_enabled "${svc}"; then
            enabled_services+=("${svc}")
        fi
    done
    
    # Resolve installation order with dependencies
    local install_order
    install_order=$(service_get_install_order "${enabled_services[@]}")
    
    log_info "Installation order: ${install_order}"
    
    local step=1
    local total=${#install_order[@]}
    
    for svc in ${install_order}; do
        log_step "${step}" "${total}" "Installing ${svc}"
        
        local install_func
        install_func=$(service_get_install_func "${svc}")
        
        if [[ -n "${install_func}" && "${install_func}" != "" ]]; then
            if declare -f "${install_func}" >/dev/null; then
                run_with_error_handling "${svc}" "${install_func}"
            else
                log_error "Install function '${install_func}' not found for service '${svc}'"
                return 1
            fi
        else
            log_warn "No install function for service '${svc}'"
        fi
        
        ((step++))
    done
    
    log_success "Installation complete!"
    print_summary
}

# ============================================================================
# NEW COMMAND HANDLERS
# ============================================================================

cmd_list_modules() {
    echo "Available modules:"
    service_list
}

cmd_health_check() {
    log_info "Running health checks..."
    logging_init
    health_check_all || true
}

cmd_backup_full() {
    log_info "Creating full backup..."
    logging_init
    backup_full
}

cmd_backup_list() {
    backup_list
}

cmd_backup_clean() {
    backup_clean
}

cmd_dashboard_install() {
    dashboard_install
}

cmd_dashboard_start() {
    log_info "Starting dashboard server on port ${DASHBOARD_PORT:-8081}..."
    cd /opt/initops-dashboard && python3 server.py "${DASHBOARD_PORT:-8081}"
}

cmd_discover() {
    logging_init
    service_discovery_generate
    service_discovery_traefik
    log_success "Service discovery generated"
}

# ============================================================================
# SUMMARY
# ============================================================================

print_summary() {
    echo
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}                    INSTALLATION SUMMARY${NC}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo
    
    local primary_ip
    primary_ip=$(get_primary_ip)
    
    # Core
    echo -e "${GREEN}✓${NC} System updated and base dependencies installed"
    echo -e "${GREEN}✓${NC} Docker installed"
    
    # VPN
    if config_service_enabled "vpn_pangolin"; then
        echo -e "${GREEN}✓${NC} VPN: Pangolin"
    fi
    if config_service_enabled "vpn_tailscale"; then
        echo -e "${GREEN}✓${NC} VPN: Tailscale"
    fi
    
    # Services
    local services=(
        "ollama:Ollama deployed (model: ${CONFIG[ollama_model]:-auto})"
        "nginx:Nginx reverse proxy configured"
        "raspap:RaspAP installed"
        "pihole:Pi-hole installed"
        "n8n:n8n installed"
        "samba:Samba installed"
        "sterling_pdf:Sterling PDF installed"
        "cockpit:Cockpit installed"
        "grafana:Grafana installed"
        "prometheus_stack:Prometheus stack installed"
    )
    
    for entry in "${services[@]}"; do
        local svc="${entry%%:*}"
        local msg="${entry#*:}"
        if config_service_enabled "${svc}"; then
            echo -e "${GREEN}✓${NC} ${msg}"
        fi
    done
    
    echo
    echo -e "${BOLD}Next Steps:${NC}"
    echo -e "  • Access dashboard at: ${CYAN}https://${primary_ip}/dashboard${NC}"
    echo -e "  • Cockpit: ${CYAN}https://${primary_ip}:9090${NC}"
    echo -e "  • Grafana: ${CYAN}http://${primary_ip}:3000${NC}"
    echo -e "  • API: ${CYAN}https://${primary_ip}/api${NC}"
    
    if config_service_enabled "n8n"; then
        echo -e "  • n8n: ${CYAN}http://${primary_ip}:5678${NC}"
    fi
    if config_service_enabled "pihole"; then
        echo -e "  • Pi-hole: ${CYAN}http://${primary_ip}:8080/admin${NC}"
    fi
    if config_service_enabled "ollama"; then
        echo -e "  • Ollama API: ${CYAN}http://${primary_ip}:11434${NC}"
    fi
    echo
}

# ============================================================================
# ENTRY POINT
# ============================================================================

main() {
    # Initialize logging first
    logging_init
    
    # Ensure we're root for actual installation (not dry-run or generate-config)
    if [[ "${DRY_RUN}" != "true" && "${GENERATE_CONFIG}" != "true" && $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi

    # Initialize state directory
    mkdir -p "${STATE_DIR}"

    # Handle reset state
    if [[ "${RESET_STATE}" == "true" ]]; then
        log_warn "Resetting installation state..."
        rm -f "${STATE_FILE}"
        log_success "State reset complete"
    fi

    # Load config file if provided
    load_config_file

    # Merge configuration (defaults < file < env < cli)
    config_merge
    config_export

    print_banner

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "DRY RUN MODE - No changes will be made"
    fi

    # OS check
    if [[ "${SKIP_OS_CHECK}" != "true" ]]; then
        check_os_compatibility
    else
        log_warn "Skipping OS compatibility check (--skip-os-check)"
    fi

    # Handle special commands
    if [[ "${GENERATE_CONFIG}" == "true" ]]; then
        generate_config_template
        exit 0
    fi

    if [[ "${LIST_MODULES}" == "true" ]]; then
        cmd_list_modules
        exit 0
    fi

    if [[ "${HEALTH_CHECK}" == "true" ]]; then
        cmd_health_check
        exit 0
    fi

    if [[ "${BACKUP_FULL}" == "true" ]]; then
        cmd_backup_full
        exit 0
    fi

    if [[ "${BACKUP_LIST}" == "true" ]]; then
        cmd_backup_list
        exit 0
    fi

    if [[ "${BACKUP_CLEAN}" == "true" ]]; then
        cmd_backup_clean
        exit 0
    fi

    if [[ "${DASHBOARD_INSTALL}" == "true" ]]; then
        cmd_dashboard_install
        exit 0
    fi

    if [[ "${DASHBOARD_START}" == "true" ]]; then
        cmd_dashboard_start
        exit 0
    fi

    if [[ "${DISCOVER}" == "true" ]]; then
        cmd_discover
        exit 0
    fi

    # Single module or full installation
    if [[ -n "${SINGLE_MODULE}" ]]; then
        log_info "Running single module: ${SINGLE_MODULE}"
        run_module "${SINGLE_MODULE}"
    else
        run_full_installation
    fi
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_args "$@"
    main
fi