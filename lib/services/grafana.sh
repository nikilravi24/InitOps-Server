#!/usr/bin/env bash
# Grafana service module for InitOps-Server
# Metrics visualization and dashboards

install_grafana() {
    if state_is_done "grafana"; then
        log_info "Grafana already installed, skipping"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would install Grafana via Docker"
        state_mark_done "grafana"
        return 0
    fi

    log_info "Installing Grafana..."

    # Ensure Docker is installed
    if ! command -v docker &>/dev/null; then
        install_docker
    fi

    # Create Grafana directories
    mkdir -p /opt/grafana/data /opt/grafana/provisioning/datasources /opt/grafana/provisioning/dashboards

    # Generate admin password if not set
    local admin_password
    admin_password=$(state_get "grafana_admin_password")
    if [[ -z "${admin_password}" ]]; then
        admin_password=$(openssl rand -base64 12)
        state_set "grafana_admin_password" "${admin_password}"
    fi

    # Pull Grafana image
    pull_docker_image "grafana/grafana:latest"

    # Run Grafana container
    docker run -d \
        --name grafana \
        --restart unless-stopped \
        -p 3000:3000 \
        -e GF_SECURITY_ADMIN_USER=admin \
        -e GF_SECURITY_ADMIN_PASSWORD="${admin_password}" \
        -e GF_INSTALL_PLUGINS=grafana-piechart-panel,grafana-worldmap-panel \
        -e GF_SERVER_ROOT_URL=%\(protocol\)://%\(domain\):%\(http_port\)/grafana/ \
        -e GF_SERVER_SERVE_FROM_SUB_PATH=true \
        -v /opt/grafana/data:/var/lib/grafana \
        -v /opt/grafana/provisioning:/etc/grafana/provisioning \
        grafana/grafana:latest

    # Wait for Grafana to be ready
    sleep 10
    wait_for_port "localhost" 3000 60

    # Setup default datasources and dashboards
    setup_grafana_provisioning

    log_success "Grafana installed"
    log_info "Access Grafana at: http://$(get_primary_ip):3000"
    log_info "Login: admin / ${admin_password}"
    log_warn "Save this password! It won't be shown again."

    state_mark_done "grafana"
}

setup_grafana_provisioning() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would setup Grafana provisioning"
        return 0
    fi

    log_info "Configuring Grafana provisioning..."

    # Prometheus datasource (for self-monitoring)
    cat > /opt/grafana/provisioning/datasources/prometheus.yaml << 'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: false
EOF

    # Node Exporter dashboard provisioning
    cat > /opt/grafana/provisioning/dashboards/dashboards.yaml << 'EOF'
apiVersion: 1
providers:
  - name: 'Default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
EOF

    # Download and install Node Exporter dashboard
    mkdir -p /opt/grafana/provisioning/dashboards
    curl -sL "https://grafana.com/api/dashboards/1860/revisions/latest/download" \
        -o /opt/grafana/provisioning/dashboards/node-exporter.json 2>/dev/null || true
}

install_prometheus_stack() {
    if state_is_done "prometheus_stack"; then
        log_info "Prometheus stack already installed, skipping"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would install Prometheus + Node Exporter + Alertmanager"
        state_mark_done "prometheus_stack"
        return 0
    fi

    log_info "Installing Prometheus monitoring stack..."

    # Create directories
    mkdir -p /opt/prometheus/data /opt/prometheus/config /opt/alertmanager/data /opt/alertmanager/config

    # Prometheus config
    cat > /opt/prometheus/config/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'docker'
    static_configs:
      - targets: ['localhost:9323']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['localhost:8080']
EOF

    # Alertmanager config
    cat > /opt/alertmanager/config/alertmanager.yml << 'EOF'
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'default'

receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://localhost:5001/'
EOF

    # Run Prometheus
    docker run -d \
        --name prometheus \
        --restart unless-stopped \
        -p 9090:9090 \
        -v /opt/prometheus/config:/etc/prometheus \
        -v /opt/prometheus/data:/prometheus \
        prom/prometheus:latest \
        --config.file=/etc/prometheus/prometheus.yml \
        --storage.tsdb.path=/prometheus \
        --web.console.libraries=/etc/prometheus/console_libraries \
        --web.console.templates=/etc/prometheus/consoles \
        --web.enable-lifecycle

    # Run Node Exporter
    docker run -d \
        --name node-exporter \
        --restart unless-stopped \
        -p 9100:9100 \
        --pid="host" \
        -v "/:/host:ro,rslave" \
        quay.io/prometheus/node-exporter:latest \
        --path.rootfs=/host

    # Run cAdvisor
    docker run -d \
        --name cadvisor \
        --restart unless-stopped \
        -p 8080:8080 \
        --volume=/:/rootfs:ro \
        --volume=/var/run:/var/run:ro \
        --volume=/sys:/sys:ro \
        --volume=/var/lib/docker/:/var/lib/docker:ro \
        --volume=/dev/disk/:/dev/disk:ro \
        gcr.io/cadvisor/cadvisor:latest

    # Run Alertmanager
    docker run -d \
        --name alertmanager \
        --restart unless-stopped \
        -p 9093:9093 \
        -v /opt/alertmanager/config:/etc/alertmanager \
        -v /opt/alertmanager/data:/alertmanager \
        prom/alertmanager:latest \
        --config.file=/etc/alertmanager/alertmanager.yml \
        --storage.path=/alertmanager

    log_success "Prometheus stack installed"
    log_info "Prometheus: http://$(get_primary_ip):9090"
    log_info "Node Exporter: http://$(get_primary_ip):9100"
    log_info "cAdvisor: http://$(get_primary_ip):8080"
    log_info "Alertmanager: http://$(get_primary_ip):9093"

    state_mark_done "prometheus_stack"
}