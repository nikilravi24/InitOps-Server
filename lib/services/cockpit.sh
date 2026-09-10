#!/usr/bin/env bash
# Cockpit service module for InitOps-Server
# System administration web UI

install_cockpit() {
    if state_is_done "cockpit"; then
        log_info "Cockpit already installed, skipping"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would install Cockpit"
        state_mark_done "cockpit"
        return 0
    fi

    log_info "Installing Cockpit..."

    # Install Cockpit
    apt update
    DEBIAN_FRONTEND=noninteractive apt install -y cockpit cockpit-pcp cockpit-machines cockpit-podman

    # Enable and start Cockpit socket
    systemctl enable --now cockpit.socket

    # Configure firewall
    ufw allow 9090/tcp

    log_success "Cockpit installed"
    log_info "Access Cockpit at: https://$(get_primary_ip):9090"
    log_info "Login with your system user credentials"

    state_mark_done "cockpit"
}

configure_cockpit() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would configure Cockpit"
        return 0
    fi

    # Enable additional modules
    systemctl enable --now cockpit-pcp.socket 2>/dev/null || true
    systemctl enable --now cockpit-machines.socket 2>/dev/null || true
    systemctl enable --now cockpit-podman.socket 2>/dev/null || true
}