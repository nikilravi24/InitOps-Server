#!/usr/bin/env bash
# Docker module for InitOps-Server
# Installs Docker Engine and Docker Compose

install_docker() {
    if state_is_done "docker"; then
        log_info "Docker already installed, skipping"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would install Docker Engine and Compose"
        state_mark_done "docker"
        return 0
    fi

    log_info "Installing Docker..."

    # Remove old versions
    apt remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc 2>/dev/null || true

    # Install prerequisites
    apt update
    DEBIAN_FRONTEND=noninteractive apt install -y ca-certificates curl gnupg lsb-release

    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Add Docker repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt update

    # Install Docker Engine, CLI, and Compose plugin
    DEBIAN_FRONTEND=noninteractive apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Enable and start Docker service
    systemctl enable --now docker

    # Add current user to docker group (if not root)
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        usermod -aG docker "${SUDO_USER}"
        log_info "Added ${SUDO_USER} to docker group (logout/login required)"
    fi

    # Verify installation
    docker --version
    docker compose version

    log_success "Docker installed successfully"

    state_mark_done "docker"
}

setup_docker_compose() {
    local project_dir="$1"
    local compose_file="${project_dir}/docker-compose.yml"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would set up docker-compose in ${project_dir}"
        return 0
    fi

    if [[ ! -f "${compose_file}" ]]; then
        log_warn "No docker-compose.yml found in ${project_dir}"
        return 1
    fi

    log_info "Starting Docker Compose services..."
    cd "${project_dir}"
    docker compose up -d

    log_success "Docker Compose services started"
}

cleanup_docker() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would clean up Docker resources"
        return 0
    fi

    log_info "Cleaning up unused Docker resources..."
    docker system prune -f
    docker volume prune -f
}