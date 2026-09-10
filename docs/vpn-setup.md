# VPN Setup Guide

## Overview

InitOps-Server supports four VPN options:

| Provider | Description | Best For |
|----------|-------------|----------|
| Pangolin | No-account VPN, privacy-first | Quick setup, no signup |
| Tailscale | Mesh VPN with device sharing | Team access, easy management |
| Both | Redundancy with both providers | Maximum flexibility |
| None | Local network only | Air-gapped, isolated environments |

## Pangolin VPN

### Installation
```bash
# Interactive
sudo ./initops.sh

# Non-interactive
./initops.sh --config config.yaml --non-interactive
# config.yaml: vpn.provider: "pangolin"
```

### Post-Installation
```bash
# Configure and connect
pangolin

# Check status
pangolin status

# Get network address
pangolin address
```

### Features
- No account required
- End-to-end encryption
- Automatic NAT traversal
- Works behind CGNAT

## Tailscale VPN

### Installation
```bash
# config.yaml: vpn.provider: "tailscale"
```

### Post-Installation
```bash
# Authenticate and connect
tailscale up

# Check status
tailscale status

# List devices
tailscale devices
```

### Features
- Mesh networking
- Device sharing
- ACLs and tailnet policies
- MagicDNS for easy naming
- Subnet routers
- Exit nodes

## Using Both VPNs

```bash
# config.yaml: vpn.provider: "both"
```

Both services run simultaneously:
- Pangolin on `pgtn0` interface
- Tailscale on `tailscale0` interface

Firewall rules are configured for both.

## No VPN (Local Only)

```bash
# config.yaml: vpn.provider: "none"
```

Services only accessible on local network. All nginx/proxy configuration still applies.

## Firewall Integration

VPN modules automatically configure UFW:
```bash
# Pangolin
ufw allow in on pgtn0
ufw allow out on pgtn0

# Tailscale
ufw allow in on tailscale0
ufw allow out on tailscale0
```

## Troubleshooting

### Pangolin won't connect
```bash
# Check service
systemctl status pangolin

# Check logs
journalctl -u pangolin -f

# Reconfigure
pangolin --reset
```

### Tailscale won't connect
```bash
# Check service
systemctl status tailscaled

# Check logs
journalctl -u tailscaled -f

# Re-authenticate
tailscale up --reset
```

### Firewall blocking VPN
```bash
# Check UFW status
ufw status verbose

# Allow VPN interfaces manually
ufw allow in on pgtn0
ufw allow in on tailscale0
```