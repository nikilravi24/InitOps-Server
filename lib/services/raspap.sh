#!/usr/bin/env bash
# RaspAP service module for InitOps-Server
# Wireless access point management

install_raspap() {
    local eth_interface="${1:-eth0}"
    local wlan_interface="${2:-wlan0}"

    if state_is_done "raspap"; then
        log_info "RaspAP already installed, skipping"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would install RaspAP on ${wlan_interface}"
        state_mark_done "raspap"
        return 0
    fi

    log_info "Installing RaspAP..."

    # Install dependencies
    apt update
    DEBIAN_FRONTEND=noninteractive apt install -y \
        hostapd dnsmasq iptables-persistent \
        lighttpd php-cgi php-common \
        git

    # Install RaspAP
    curl -sL https://install.raspap.com | bash -s -- --yes

    # Configure interfaces
    configure_raspap_interfaces "${eth_interface}" "${wlan_interface}"

    # Enable services
    systemctl enable --now hostapd
    systemctl enable --now dnsmasq
    systemctl enable --now lighttpd

    log_success "RaspAP installed"
    log_info "Access RaspAP at: http://$(get_primary_ip)"
    log_info "Default login: admin / secret"

    state_mark_done "raspap"
}

configure_raspap_interfaces() {
    local eth_interface="$1"
    local wlan_interface="$2"

    log_info "Configuring network interfaces..."

    # Backup original interfaces
    cp /etc/dhcpcd.conf /etc/dhcpcd.conf.bak 2>/dev/null || true

    # Configure dhcpcd for static AP IP
    cat >> /etc/dhcpcd.conf << EOF

# RaspAP configuration
interface ${wlan_interface}
    static ip_address=10.3.141.1/24
    nohook wpa_supplicant
EOF

    # Configure dnsmasq
    cat > /etc/dnsmasq.d/raspap.conf << EOF
interface=${wlan_interface}
dhcp-range=10.3.141.50,10.3.141.255,255.255.255.0,24h
domain=raspap.local
address=/raspap.local/10.3.141.1
EOF

    # Configure hostapd
    cat > /etc/hostapd/hostapd.conf << EOF
interface=${wlan_interface}
driver=nl80211
ssid=InitOps-AP
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=InitOpsServer
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

    # Update hostapd default
    sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

    # Enable IP forwarding
    echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-raspap.conf
    sysctl -p /etc/sysctl.d/99-raspap.conf

    # Configure NAT
    iptables -t nat -A POSTROUTING -o "${eth_interface}" -j MASQUERADE
    iptables -A FORWARD -i "${eth_interface}" -o "${wlan_interface}" -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i "${wlan_interface}" -o "${eth_interface}" -j ACCEPT

    # Save iptables rules
    netfilter-persistent save
}