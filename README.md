# InitOps-Server

> **Multi-purpose utility server setup script for Linux** — Automates bootstrapping, provisioning, and environment initialization for Linux systems.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-green.svg)]
[![Platform: Linux](https://img.shields.io/badge/Platform-Linux-blue.svg)]
[![Status: Active Development](https://img.shields.io/badge/Status-Active%20Development-brightgreen.svg)]

---

## 🎯 Overview

**InitOps-Server** (formerly *Pi Server Setup v3*) is an interactive, modular setup script that transforms a fresh Linux installation into a production-ready utility server. Designed for **Linux systems** (ARM and x86_64), it provides:

- **Modular VPN support** — Pangolin, Tailscale, both, or none
- **Hardware-aware LLM deployment** — Ollama with automatic model selection based on system resources
- **Idempotent design** — Safe to re-run; tracks state to avoid duplicate operations
- **Cross-platform execution** — Run from any Linux host
- **Single sign-on** — Unified authentication across all services via nginx reverse proxy
- **Production-ready** — Hardened defaults with backward compatibility

> **Project Status**: Active development. Core modules functional; dashboard UI and SSO integration in progress.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        InitOps-Server                            │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐  │
│  │     Frontend     │  │    Middleware    │  │   Backend    │  │
│  ├──────────────────┤  ├──────────────────┤  ├──────────────┤  │
│  │ • Unified Dash.  │  │ • nginx          │  │ • Cockpit    │  │
│  │ • Drag-drop UI   │  │   (reverse proxy)│  │ • Grafana    │  │
│  │ • Single Auth    │  │ • Auth Gateway   │  │ • Docker     │  │
│  │ • Service Widgets│  │ • TLS/SSL        │  │   Services   │  │
│  └──────────────────┘  └──────────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Component Mapping

| Layer | Components | Purpose |
|-------|------------|---------|
| **Frontend** | Common Dashboard, Drag-and-drop UI, Single Auth Portal | User-facing unified interface |
| **Middleware** | nginx (reverse proxy + auth), SSL/TLS termination | Traffic routing & authentication |
| **Backend** | Cockpit, Grafana, Docker services | System admin, monitoring, containers |

---

## 🚀 Features

### Core Services

| Service | Description | Deployment | Status |
|---------|-------------|------------|--------|
| **RaspAP** | Wireless access point management + firewall | Native | ✅ Planned |
| **Pi-hole** | Network-wide ad blocking & DNS filtering | Docker | ✅ Planned |
| **n8n** | Workflow automation for user & system tasks | Docker | ✅ Planned |
| **Ollama** | Local LLM inference (hardware-aware model select) | Docker | ✅ Planned |
| **Samba** | Network file sharing (SMB/CIFS) for cross-platform access | Native | ✅ Planned |
| **Sterling PDF** | Web-based PDF toolkit (merge, split, convert, sign, OCR) | Docker | ✅ Planned |
| **Firewall** | UFW/iptables managed via RaspAP integration | Native | ✅ Planned |

### Management & Monitoring

| Component | Purpose | Access Via |
|-----------|---------|------------|
| **Cockpit** | System administration web UI | Dashboard / Direct |
| **Grafana** | Metrics visualization & dashboards | Dashboard / Direct |
| **nginx** | Reverse proxy + single auth gateway | All services |
| **Docker** | Container orchestration for services | CLI / Dashboard |

---

## 📋 Requirements

### Hardware (Minimum)

| Resource | Minimum | Recommended | Notes |
|----------|---------|-------------|-------|
| **CPU** | 2+ cores (ARM64/x86_64) | 4+ cores | SBCs, mini PCs, VMs |
| **RAM** | 2 GB | 8 GB+ | 4 GB+ for Ollama |
| **Storage** | 16 GB free | 64 GB+ | SSD/NVMe preferred |
| **Network** | Ethernet | 1 Gbps | WiFi for AP mode only |

### Software

| Requirement | Details |
|-------------|---------|
| **Privileges** | `sudo` access required |
| **Tools** | `curl`, `git`, `bash` (pre-installed on most distros) |
| **Remote Host** | Any Linux |

---

## 🛠️ Installation

### Quick Start (Interactive — On Target Machine)

```bash
# Clone the repository
git clone https://github.com/SanjaiPS-tech/IntiOps-Server.git
cd IntiOps-Server

# Make executable and run
chmod +x initops.sh
sudo ./initops.sh
```

### Non-Interactive (Automated / CI)

```bash
# Generate config template first
./initops.sh --generate-config > config.yaml

# Edit config.yaml with your settings, then:
./initops.sh --config config.yaml --non-interactive
```

### Installation Modes Comparison

| Mode | Use Case | Flags |
|------|----------|-------|
| **Interactive** | First-time setup, exploration | (default) |
| **Non-interactive** | Automation, CI/CD, re-deploys | `--config file --non-interactive` |
| **Remote** | Headless devices, edge deployments | `--target user@host` |

---

## ⚙️ Configuration

### VPN Options

| Option | Description | Best For |
|--------|-------------|----------|
| `pangolin` | Pangolin VPN (no account required) | Privacy-first, no signup |
| `tailscale` | Tailscale mesh VPN | Easy mesh, device sharing |
| `both` | Both Pangolin and Tailscale | Redundancy, flexibility |
| `none` | No VPN (local network only) | Air-gapped, local-only |

### Configuration File Example (`config.yaml`)

```yaml
# InitOps-Server Configuration
vpn:
  provider: "pangolin"          # pangolin | tailscale | both | none
  
ollama:
  enabled: true
  model: "auto"                 # auto | specific model name
  gpu_acceleration: true        # Use GPU if available

services:
  raspap: true
  pihole: true
  n8n: true
  cockpit: true
  grafana: true

nginx:
  domain: "local"               # local | your.domain.com
  ssl: "self-signed"            # self-signed | letsencrypt | none
  auth:
    provider: "basic"           # basic | oidc | authelia
    users:
      - "admin:hashed_password"

network:
  interface: "eth0"             # Primary interface
  ap_interface: "wlan0"         # For RaspAP (wireless interfaces)
```

Generate with: `./initops.sh --generate-config`

---

## 🔐 Single Sign-On (SSO)

All services accessible through unified nginx reverse proxy:

- **Single authentication** — One login for Dashboard, Cockpit, Grafana, n8n, Pi-hole
- **Role-based access** — Admin / Operator / Viewer roles (planned)
- **TLS termination** — Automatic Let's Encrypt or self-signed certs
- **Drag-and-drop dashboard** — Rearrange service widgets visually (planned)
- **Auth providers** — Basic auth (default), OIDC, Authelia (planned)

---

## 📁 Project Structure

```
InitOps-Server/
├── initops.sh                 # Main entry point
├── lib/
│   ├── core.sh                # Core utilities (logging, state, OS detection)
│   ├── vpn.sh                 # VPN module (Pangolin/Tailscale)
│   ├── docker.sh              # Docker + compose management
│   ├── ollama.sh              # Ollama hardware-aware deployment
│   ├── nginx.sh               # Reverse proxy + auth
│   └── services/              # Individual service modules
│       ├── raspap.sh
│       ├── pihole.sh
│       ├── n8n.sh
│       ├── cockpit.sh
│       └── grafana.sh
├── config/
│   ├── default.yaml           # Default configuration
│   └── examples/              # Example configs (pi.yaml, server.yaml, minimal.yaml)
├── state/
│   └── .initops-state         # Idempotency tracking (auto-generated)
├── tests/
│   └── bats/                  # BATS integration tests
└── docs/                      # Additional documentation
    ├── architecture.md
    ├── vpn-setup.md
    └── troubleshooting.md
```

---

## 🧪 Testing

```bash
# Run all tests
bats tests/bats/

# Test specific module
bats tests/bats/vpn.bats
bats tests/bats/docker.bats

# Lint shell scripts
shellcheck lib/*.sh lib/services/*.sh initops.sh
```

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- **Idempotency first** — Every operation must be safely re-runnable
- **State tracking** — Use `lib/core.sh` state functions (`state_set`, `state_get`, `state_check`)
- **Modular design** — Each service in `lib/services/`
- **Shellcheck clean** — `shellcheck lib/*.sh lib/services/*.sh`
- **Test-driven** — Add BATS tests for new features

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

- [RaspAP](https://raspap.com/) — Wireless AP management
- [Pi-hole](https://pi-hole.net/) — Network-wide ad blocking
- [n8n](https://n8n.io/) — Workflow automation
- [Ollama](https://ollama.ai/) — Local LLM inference
- [Cockpit](https://cockpit-project.org/) — Server admin UI
- [Grafana](https://grafana.com/) — Observability platform
- [Pangolin](https://pangolin.com/) — No-account VPN
- [Tailscale](https://tailscale.com/) — Mesh VPN

---

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/SanjaiPS-tech/IntiOps-Server/issues)
- **Discussions**: [GitHub Discussions](https://github.com/SanjaiPS-tech/IntiOps-Server/discussions)
- **Wiki**: [Project Wiki](https://github.com/SanjaiPS-tech/IntiOps-Server/wiki) (coming soon)

---

<div align="center">
  <strong>Built for homelabs, edge deployments, and self-hosted enthusiasts</strong><br>
  <sub>Linux-native • Hardware-aware • Cross-platform</sub>
</div>