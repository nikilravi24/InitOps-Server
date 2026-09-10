#!/usr/bin/env bash
# VPN module for InitOps-Server
# Supports Pangolin, Tailscale, both, or none

install_vpn() {
    local provider="$1"

    case "${provider}" in
        pangolin)
            install_pangolin
            ;;
        tailscale)
            install_tailscale
            ;;
        both)
            install_pangolin
            install_tailscale
            ;;
        none)
            log_info "VPN disabled (provider: none)"
            ;;
        *)
            log_error "Unknown VPN provider: ${provider}"
            return 1
            ;;
    esac
}

install_pangolin() {
    if state_is_done "vpn_pangolin"; then
        log_info "Pangolin already installed, skipping"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would install Pangolin VPN"
        state_mark_done "vpn_pangolin"
        return 0
    fi

    log_info "Installing Pangolin VPN..."

    # Install Pangolin using official script
    curl -fsSL https://install.pangolin.com | bash

    # Enable and start service
    systemctl enable --now pangolin

    log_success "Pangolin VPN installed and started"
    log_info "Run 'pangolin' to configure and get your network address"

    state_mark_done "vpn_pangolin"
}

install_tailscale() {
    if state_is_done "vpn_tailscale"; then
        log_info "Tailscale already installed, skipping"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would install Tailscale VPN"
        state_mark_done "vpn_tailscale"
        return 0
    fi

    log_info "Installing Tailscale VPN..."

    # Add Tailscale repository
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarch.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list

    apt update
    DEBIAN_FRONTEND=noninteractive apt install -y tailscale

    # Enable and start service
    systemctl enable --now tailscaled

    log_success "Tailscale installed"
    log_info "Run 'tailscale up' to authenticate and connect"

    state_mark_done "vpn_tailscale"
}

configure_vpn_firewall() {
    local provider="$1"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would configure firewall for ${provider}"
        return 0
    fi

    case "${provider}" in
        pangolin)
            ufw allow in on pgtn0
            ufw allow out on pgtn0
            ;;
        tailscale)
            ufw allow in on tailscale0
            ufw allow out on tailscale0
            ;;
    esac
}