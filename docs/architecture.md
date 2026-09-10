# InitOps-Server Architecture

## Overview

InitOps-Server follows a layered architecture with three main layers:

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

## Layer Responsibilities

### Frontend Layer
- **Unified Dashboard**: Single pane of glass for all services
- **Drag-and-drop UI**: Customizable service widgets
- **Single Authentication Portal**: One login for all services

### Middleware Layer
- **nginx Reverse Proxy**: Routes traffic to backend services
- **Authentication Gateway**: Handles auth (Basic, OIDC, Authelia)
- **TLS/SSL Termination**: Manages certificates (Let's Encrypt, self-signed)

### Backend Layer
- **Cockpit**: System administration
- **Grafana**: Metrics visualization
- **Docker Services**: Containerized applications (Pi-hole, n8n, Ollama, Sterling PDF, etc.)

## Data Flow

1. User accesses `https://server.domain.com`
2. nginx terminates TLS
3. Authentication gateway validates credentials
4. Request routed to appropriate backend service
5. Service responds through nginx to user

## State Management

Idempotency is achieved through state tracking in `state/.initops-state`:
- Each module tracks its installation state
- Re-runs safely skip completed steps
- State keys follow pattern: `<module>_<action>`

## Module System

Each service is a separate module in `lib/services/`:
- Independent installation and configuration
- Shared utilities from `lib/core.sh`
- Docker-based services use `lib/docker.sh`