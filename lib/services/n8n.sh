#!/usr/bin/env bash
# n8n service module for InitOps-Server
# Workflow automation

install_n8n() {
    if state_is_done "n8n"; then
        log_info "n8n already installed, skipping"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would install n8n via Docker"
        state_mark_done "n8n"
        return 0
    fi

    log_info "Installing n8n..."

    # Ensure Docker is installed
    if ! command -v docker &>/dev/null; then
        install_docker
    fi

    # Create n8n directory
    mkdir -p /opt/n8n

    # Generate encryption key if not set
    local encryption_key
    encryption_key=$(state_get "n8n_encryption_key")
    if [[ -z "${encryption_key}" ]]; then
        encryption_key=$(openssl rand -hex 16)
        state_set "n8n_encryption_key" "${encryption_key}"
    fi

    # Pull n8n image
    pull_docker_image "n8nio/n8n:latest"

    # Run n8n container
    docker run -d \
        --name n8n \
        --restart unless-stopped \
        -p 5678:5678 \
        -e N8N_HOST="0.0.0.0" \
        -e N8N_PORT=5678 \
        -e N8N_PROTOCOL=http \
        -e N8N_ENCRYPTION_KEY="${encryption_key}" \
        -e GENERIC_TIMEZONE="$(cat /etc/timezone 2>/dev/null || echo UTC)" \
        -v /opt/n8n:/home/node/.n8n \
        n8nio/n8n:latest

    # Wait for n8n to be ready
    sleep 10
    wait_for_port "localhost" 5678 60

    log_success "n8n installed"
    log_info "Access n8n at: http://$(get_primary_ip):5678"
    log_info "Encryption key saved to state (needed for backups/restore)"

    state_mark_done "n8n"
}

backup_n8n() {
    local backup_dir="/opt/backups/n8n/$(date +%Y%m%d_%H%M%S)"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would backup n8n to ${backup_dir}"
        return 0
    fi

    mkdir -p "${backup_dir}"
    docker exec n8n tar czf - /home/node/.n8n > "${backup_dir}/n8n_backup.tar.gz"
    log_success "n8n backed up to ${backup_dir}"
}