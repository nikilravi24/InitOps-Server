#!/usr/bin/env bash
# Samba service module for InitOps-Server
# Network file sharing (SMB/CIFS) for cross-platform access

install_samba() {
    if state_is_done "samba"; then
        log_info "Samba already installed, skipping"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would install and configure Samba"
        state_mark_done "samba"
        return 0
    fi

    log_info "Installing Samba..."

    # Install Samba
    apt update
    DEBIAN_FRONTEND=noninteractive apt install -y samba samba-common-bin

    # Create Samba directories
    mkdir -p /srv/samba/public
    mkdir -p /srv/samba/private

    # Set permissions
    chmod 1777 /srv/samba/public  # Sticky bit for public share
    chmod 770 /srv/samba/private

    # Create samba group and add users
    groupadd -f sambashare
    chgrp sambashare /srv/samba/private

    # Configure Samba
    configure_samba

    # Create default users
    setup_samba_users

    # Enable and start services
    systemctl enable --now smbd nmbd

    # Configure firewall
    ufw allow 'Samba'

    log_success "Samba installed and configured"
    log_info "Public share: \\\\$(hostname)\\public (no auth required)"
    log_info "Private share: \\\\$(hostname)\\private (requires auth)"

    state_mark_done "samba"
}

configure_samba() {
    local config_file="/etc/samba/smb.conf"

    # Backup original config
    cp "${config_file}" "${config_file}.bak" 2>/dev/null || true

    log_info "Generating Samba configuration..."

    cat > "${config_file}" << 'EOF'
[global]
    workgroup = WORKGROUP
    server string = InitOps-Server (%v)
    netbios name = INITOPS
    security = user
    map to guest = Bad User
    dns proxy = no
    log file = /var/log/samba/log.%m
    max log size = 1000
    logging = file
    panic action = /usr/share/samba/panic-action %d
    server role = standalone server
    obey pam restrictions = yes
    unix password sync = yes
    passwd program = /usr/bin/passwd %u
    passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .
    pam password change = yes
    usershare allow guests = yes
    usershare max shares = 100
    usershare owner only = yes
    force create mode = 0664
    force directory mode = 0775

# Public share - no authentication required
[public]
    path = /srv/samba/public
    browseable = yes
    read only = no
    guest ok = yes
    guest only = yes
    force user = nobody
    force group = nogroup
    create mask = 0664
    directory mask = 0775

# Private share - authentication required
[private]
    path = /srv/samba/private
    browseable = yes
    read only = no
    guest ok = no
    valid users = @sambashare
    create mask = 0660
    directory mask = 0770
    force group = sambashare

# Home directories
[homes]
    comment = Home Directories
    browseable = no
    read only = no
    create mask = 0700
    directory mask = 0700
    valid users = %S
EOF

    # Test configuration
    testparm -s
}

setup_samba_users() {
    # Create a default samba user if running interactively
    if [[ "${NON_INTERACTIVE}" != "true" ]]; then
        if prompt_yes_no "Create a Samba user for private share access?" "y"; then
            local username
            username=$(prompt_input "Username" "sambauser")
            local password
            password=$(prompt_password "Password for ${username}")

            # Create system user if not exists
            id "${username}" &>/dev/null || useradd -M -s /usr/sbin/nologin -G sambashare "${username}"

            # Set Samba password
            (echo "${password}"; echo "${password}") | smbpasswd -a "${username}"
            smbpasswd -e "${username}"

            log_success "Samba user '${username}' created"
        fi
    else
        log_info "Non-interactive mode: skipping user creation"
        log_info "Run 'smbpasswd -a <username>' manually to add users"
    fi
}

add_samba_user() {
    local username="$1"
    local password="$2"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would add Samba user: ${username}"
        return 0
    fi

    id "${username}" &>/dev/null || useradd -M -s /usr/sbin/nologin -G sambashare "${username}"
    (echo "${password}"; echo "${password}") | smbpasswd -a "${username}"
    smbpasswd -e "${username}"
    log_success "Samba user '${username}' added"
}