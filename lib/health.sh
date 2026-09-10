#!/usr/bin/env bash
# Health Checks for InitOps-Server
# Service health verification functions

# ============================================================================
# CORE HEALTH CHECKS
# ============================================================================

health_system_update() {
    # Check if system was updated recently (within 24h)
    local stamp_file="/var/lib/apt/periodic/update-success-stamp"
    [[ -f "$stamp_file" ]] && [[ $(($(date +%s) - $(stat -c %Y "$stamp_file"))) -lt 86400 ]]
}

health_base_deps() {
    # Check if key packages are installed
    local pkgs=("curl" "wget" "git" "gnupg2" "jq" "yq" "ufw" "fail2ban")
    for pkg in "${pkgs[@]}"; do
        dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" || return 1
    done
    return 0
}

health_docker() {
    command -v docker &>/dev/null && docker info &>/dev/null
}

# ============================================================================
# VPN HEALTH CHECKS
# ============================================================================

health_pangolin() {
    systemctl is-active --quiet pangolin 2>/dev/null
}

health_tailscale() {
    systemctl is-active --quiet tailscaled 2>/dev/null && tailscale status &>/dev/null
}

# ============================================================================
# PLATFORM HEALTH CHECKS
# ============================================================================

health_ollama() {
    curl -sf http://localhost:11434/api/version &>/dev/null
}

health_nginx() {
    systemctl is-active --quiet nginx 2>/dev/null && nginx -t &>/dev/null
}

# ============================================================================
# APPLICATION HEALTH CHECKS
# ============================================================================

health_raspap() {
    systemctl is-active --quiet hostapd 2>/dev/null && \
    systemctl is-active --quiet dnsmasq 2>/dev/null && \
    systemctl is-active --quiet lighttpd 2>/dev/null
}

health_pihole() {
    docker ps --filter "name=pihole" --filter "status=running" --format "{{.Names}}" | grep -q "^pihole$"
}

health_n8n() {
    docker ps --filter "name=n8n" --filter "status=running" --format "{{.Names}}" | grep -q "^n8n$" && \
    curl -sf http://localhost:5678/healthz &>/dev/null
}

health_samba() {
    systemctl is-active --quiet smbd 2>/dev/null && \
    systemctl is-active --quiet nmbd 2>/dev/null && \
    testparm -s &>/dev/null
}

health_sterling_pdf() {
    docker ps --filter "name=sterling-pdf" --filter "status=running" --format "{{.Names}}" | grep -q "^sterling-pdf$" && \
    curl -sf http://localhost:3001 &>/dev/null
}

health_cockpit() {
    systemctl is-active --quiet cockpit.socket 2>/dev/null
}

health_grafana() {
    docker ps --filter "name=grafana" --filter "status=running" --format "{{.Names}}" | grep -q "^grafana$" && \
    curl -sf http://localhost:3000/api/health &>/dev/null
}

health_prometheus_stack() {
    docker ps --filter "name=prometheus" --filter "status=running" --format "{{.Names}}" | grep -q "^prometheus$" && \
    docker ps --filter "name=node-exporter" --filter "status=running" --format "{{.Names}}" | grep -q "^node-exporter$" && \
    docker ps --filter "name=cadvisor" --filter "status=running" --format "{{.Names}}" | grep -q "^cadvisor$" && \
    docker ps --filter "name=alertmanager" --filter "status=running" --format "{{.Names}}" | grep -q "^alertmanager$" && \
    curl -sf http://localhost:9090/-/healthy &>/dev/null
}

# ============================================================================
# COMPOSITE HEALTH CHECKS
# ============================================================================

# Check all enabled services
health_check_services() {
    local services=("$@")
    local results=()
    local overall=0
    
    for svc in "${services[@]}"; do
        local func="health_${svc}"
        if declare -f "$func" >/dev/null; then
            if $func; then
                results+=("$svc:healthy")
            else
                results+=("$svc:unhealthy")
                overall=1
            fi
        else
            results+=("$svc:unknown")
            overall=1
        fi
    done
    
    # Print results
    for result in "${results[@]}"; do
        echo "$result"
    done
    
    return $overall
}

# Get service status for dashboard
health_get_status_json() {
    local services=("$@")
    local json="{"
    local first=true
    
    for svc in "${services[@]}"; do
        local func="health_${svc}"
        local status="unknown"
        local details=""
        
        if declare -f "$func" >/dev/null; then
            if $func; then
                status="healthy"
            else
                status="unhealthy"
            fi
        fi
        
        # Get additional details
        case "$svc" in
            ollama)
                details=$(curl -sf http://localhost:11434/api/tags 2>/dev/null | jq -c '.models | length' 2>/dev/null || echo "0")
                details="\"models\":$details"
                ;;
            docker)
                details=$(docker info --format '{{.ContainersRunning}}/{{.Containers}}' 2>/dev/null || echo "0/0")
                details="\"containers\":\"$details\""
                ;;
            grafana)
                details=$(curl -sf http://localhost:3000/api/dashboards/home 2>/dev/null | jq -c '.dashboards | length' 2>/dev/null || echo "0")
                details="\"dashboards\":$details"
                ;;
        esac
        
        [[ "$first" == "true" ]] && first=false || json+=","
        json+="\"$svc\":{\"status\":\"$status\""
        [[ -n "$details" ]] && json+=",$details"
        json+="}"
    done
    
    json+="}"
    echo "$json"
}

# Quick system health summary
health_summary() {
    local services=(
        "system_update"
        "base_deps"
        "docker"
        "ollama"
        "nginx"
        "raspap"
        "pihole"
        "n8n"
        "samba"
        "sterling_pdf"
        "cockpit"
        "grafana"
        "prometheus_stack"
    )
    
    # Filter to only enabled services
    local enabled=()
    for svc in "${services[@]}"; do
        if config_service_enabled "$svc" 2>/dev/null; then
            enabled+=("$svc")
        fi
    done
    
    health_check_services "${enabled[@]}"
}