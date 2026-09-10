#!/usr/bin/env bash
# Backup & Restore System for InitOps-Server
# Unified backup/restore for all services

# ============================================================================
# BACKUP CONFIGURATION
# ============================================================================

BACKUP_ROOT="${BACKUP_ROOT:-/opt/backups/initops}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
BACKUP_COMPRESS="${BACKUP_COMPRESS:-true}"

# ============================================================================
# CORE BACKUP FUNCTIONS
# ============================================================================

# Create backup directory structure
backup_init() {
    mkdir -p "$BACKUP_ROOT"/{configs,services,databases,logs}
}

# Generate backup manifest
backup_manifest_create() {
    local backup_dir="$1"
    local manifest_file="$backup_dir/manifest.json"
    
    cat > "$manifest_file" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "hostname": "$(hostname)",
    "version": "${VERSION:-unknown}",
    "services": []
}
EOF
}

# Add service to manifest
backup_manifest_add_service() {
    local backup_dir="$1"
    local service="$2"
    local status="$3"
    local details="${4:-{}}"
    local manifest_file="$backup_dir/manifest.json"
    
    local tmp_file=$(mktemp)
    jq --arg svc "$service" --arg status "$status" --argjson details "$details" \
        '.services += [{"name":$svc,"status":$status,"details":$details}]' \
        "$manifest_file" > "$tmp_file" && mv "$tmp_file" "$manifest_file"
}

# ============================================================================
# SERVICE BACKUP FUNCTIONS
# ============================================================================

# Backup configuration files
backup_configs() {
    local backup_dir="$1"
    local config_backup_dir="$backup_dir/configs"
    mkdir -p "$config_backup_dir"
    
    log_info "Backing up configuration files..."
    
    # Main config
    [[ -f "$CONFIG_DIR/default.yaml" ]] && cp "$CONFIG_DIR/default.yaml" "$config_backup_dir/"
    [[ -f "$STATE_FILE" ]] && cp "$STATE_FILE" "$config_backup_dir/initops-state"
    
    # Nginx config
    [[ -f "/etc/nginx/sites-available/initops" ]] && cp "/etc/nginx/sites-available/initops" "$config_backup_dir/nginx.conf"
    [[ -f "/etc/nginx/.htpasswd" ]] && cp "/etc/nginx/.htpasswd" "$config_backup_dir/htpasswd"
    
    # Samba config
    [[ -f "/etc/samba/smb.conf" ]] && cp "/etc/samba/smb.conf" "$config_backup_dir/smb.conf"
    
    # System configs
    cp -r /etc/hostapd "$config_backup_dir/" 2>/dev/null || true
    cp -r /etc/dnsmasq.d "$config_backup_dir/" 2>/dev/null || true
    cp /etc/dhcpcd.conf "$config_backup_dir/" 2>/dev/null || true
    
    log_success "Configuration backup complete"
}

# Backup Docker volumes
backup_docker_volumes() {
    local backup_dir="$1"
    local volumes_backup_dir="$backup_dir/volumes"
    mkdir -p "$volumes_backup_dir"
    
    log_info "Backing up Docker volumes..."
    
    local volumes=(
        "pihole_data:/opt/pihole"
        "n8n_data:/opt/n8n"
        "grafana_data:/opt/grafana"
        "prometheus_data:/opt/prometheus"
        "alertmanager_data:/opt/alertmanager"
        "sterling_pdf_data:/opt/sterling-pdf"
    )
    
    for vol in "${volumes[@]}"; do
        local name="${vol%%:*}"
        local path="${vol#*:}"
        
        if [[ -d "$path" ]]; then
            log_debug "Backing up volume: $name from $path"
            if [[ "$BACKUP_COMPRESS" == "true" ]]; then
                tar czf "$volumes_backup_dir/${name}.tar.gz" -C "$(dirname "$path")" "$(basename "$path")" 2>/dev/null || true
            else
                cp -r "$path" "$volumes_backup_dir/$name" 2>/dev/null || true
            fi
        fi
    done
    
    log_success "Docker volumes backup complete"
}

# Backup databases
backup_databases() {
    local backup_dir="$1"
    local db_backup_dir="$backup_dir/databases"
    mkdir -p "$db_backup_dir"
    
    log_info "Backing up databases..."
    
    # Pi-hole gravity database
    if docker ps --filter "name=pihole" --filter "status=running" --format "{{.Names}}" | grep -q "^pihole$"; then
        docker exec pihole sqlite3 /etc/pihole/gravity.db .dump > "$db_backup_dir/pihole-gravity.sql" 2>/dev/null || true
    fi
    
    # Grafana database
    if docker ps --filter "name=grafana" --filter "status=running" --format "{{.Names}}" | grep -q "^grafana$"; then
        docker exec grafana sqlite3 /var/lib/grafana/grafana.db .dump > "$db_backup_dir/grafana.db.sql" 2>/dev/null || true
    fi
    
    log_success "Database backup complete"
}

# Individual service backup functions
backup_ollama() {
    local backup_dir="${1:-$BACKUP_ROOT/ollama-$(date +%Y%m%d_%H%M%S)}"
    mkdir -p "$backup_dir"
    
    log_info "Backing up Ollama models..."
    
    # List installed models
    ollama list > "$backup_dir/models.txt" 2>/dev/null || true
    
    # Backup model data (if using default storage)
    if [[ -d "/usr/share/ollama/.ollama/models" ]]; then
        tar czf "$backup_dir/models.tar.gz" -C /usr/share/ollama .ollama/models 2>/dev/null || true
    fi
    
    backup_manifest_add_service "$backup_dir" "ollama" "completed" '{"models_file":"models.txt"}'
    log_success "Ollama backup complete: $backup_dir"
}

backup_pihole() {
    local backup_dir="${1:-$BACKUP_ROOT/pihole-$(date +%Y%m%d_%H%M%S)}"
    mkdir -p "$backup_dir"
    
    log_info "Backing up Pi-hole..."
    
    # Export teleporter backup
    if docker ps --filter "name=pihole" --filter "status=running" --format "{{.Names}}" | grep -q "^pihole$"; then
        docker exec pihole pihole -a -t > "$backup_dir/pihole-teleporter.tar.gz" 2>/dev/null || true
    fi
    
    # Backup configs
    cp -r /opt/pihole "$backup_dir/" 2>/dev/null || true
    
    backup_manifest_add_service "$backup_dir" "pihole" "completed" '{}'
    log_success "Pi-hole backup complete: $backup_dir"
}

backup_n8n() {
    local backup_dir="${1:-$BACKUP_ROOT/n8n-$(date +%Y%m%d_%H%M%S)}"
    mkdir -p "$backup_dir"
    
    log_info "Backing up n8n..."
    
    # Backup workflows and credentials
    if docker ps --filter "name=n8n" --filter "status=running" --format "{{.Names}}" | grep -q "^n8n$"; then
        docker exec n8n tar czf - /home/node/.n8n > "$backup_dir/n8n_backup.tar.gz" 2>/dev/null || true
    fi
    
    # Backup encryption key from state
    local enc_key
    enc_key=$(state_get "n8n_encryption_key")
    [[ -n "$enc_key" ]] && echo "$enc_key" > "$backup_dir/encryption_key.txt"
    
    backup_manifest_add_service "$backup_dir" "n8n" "completed" '{}'
    log_success "n8n backup complete: $backup_dir"
}

backup_grafana() {
    local backup_dir="${1:-$BACKUP_ROOT/grafana-$(date +%Y%m%d_%H%M%S)}"
    mkdir -p "$backup_dir"
    
    log_info "Backing up Grafana..."
    
    # Export dashboards via API
    if curl -sf http://localhost:3000/api/health &>/dev/null; then
        curl -sf "http://admin:${CONFIG[grafana_admin_password]}@localhost:3000/api/search" \
            > "$backup_dir/dashboards.json" 2>/dev/null || true
    fi
    
    # Backup provisioning
    cp -r /opt/grafana/provisioning "$backup_dir/" 2>/dev/null || true
    
    backup_manifest_add_service "$backup_dir" "grafana" "completed" '{}'
    log_success "Grafana backup complete: $backup_dir"
}

backup_prometheus_stack() {
    local backup_dir="${1:-$BACKUP_ROOT/prometheus-$(date +%Y%m%d_%H%M%S)}"
    mkdir -p "$backup_dir"
    
    log_info "Backing up Prometheus stack..."
    
    # Backup Prometheus data
    if docker ps --filter "name=prometheus" --filter "status=running" --format "{{.Names}}" | grep -q "^prometheus$"; then
        # Create snapshot via API
        curl -sf -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot \
            > "$backup_dir/prometheus_snapshot.json" 2>/dev/null || true
    fi
    
    # Backup configs
    cp -r /opt/prometheus/config "$backup_dir/prometheus_config" 2>/dev/null || true
    cp -r /opt/alertmanager/config "$backup_dir/alertmanager_config" 2>/dev/null || true
    
    backup_manifest_add_service "$backup_dir" "prometheus_stack" "completed" '{}'
    log_success "Prometheus stack backup complete: $backup_dir"
}

backup_samba() {
    local backup_dir="${1:-$BACKUP_ROOT/samba-$(date +%Y%m%d_%H%M%S)}"
    mkdir -p "$backup_dir"
    
    log_info "Backing up Samba..."
    
    # Backup config
    cp /etc/samba/smb.conf "$backup_dir/" 2>/dev/null || true
    
    # Backup user database
    pdbedit -L -w > "$backup_dir/samba_users.txt" 2>/dev/null || true
    
    # Backup TDB files
    cp /var/lib/samba/*.tdb "$backup_dir/" 2>/dev/null || true
    
    backup_manifest_add_service "$backup_dir" "samba" "completed" '{}'
    log_success "Samba backup complete: $backup_dir"
}

backup_sterling_pdf() {
    local backup_dir="${1:-$BACKUP_ROOT/sterling-pdf-$(date +%Y%m%d_%H%M%S)}"
    mkdir -p "$backup_dir"
    
    log_info "Backing up Sterling PDF..."
    
    # Backup data directory
    cp -r /opt/sterling-pdf/data "$backup_dir/" 2>/dev/null || true
    
    backup_manifest_add_service "$backup_dir" "sterling_pdf" "completed" '{}'
    log_success "Sterling PDF backup complete: $backup_dir"
}

# ============================================================================
# RESTORE FUNCTIONS
# ============================================================================

restore_ollama() {
    local backup_dir="$1"
    
    log_info "Restoring Ollama from $backup_dir..."
    
    if [[ -f "$backup_dir/models.tar.gz" ]]; then
        tar xzf "$backup_dir/models.tar.gz" -C / 2>/dev/null || true
        systemctl restart ollama
    fi
    
    log_success "Ollama restore complete"
}

restore_pihole() {
    local backup_dir="$1"
    
    log_info "Restoring Pi-hole from $backup_dir..."
    
    if [[ -f "$backup_dir/pihole-teleporter.tar.gz" ]]; then
        docker exec -i pihole pihole -a -r < "$backup_dir/pihole-teleporter.tar.gz" 2>/dev/null || true
    fi
    
    if [[ -d "$backup_dir/pihole" ]]; then
        cp -r "$backup_dir/pihole/"* /opt/pihole/ 2>/dev/null || true
        docker restart pihole
    fi
    
    log_success "Pi-hole restore complete"
}

restore_n8n() {
    local backup_dir="$1"
    
    log_info "Restoring n8n from $backup_dir..."
    
    if [[ -f "$backup_dir/n8n_backup.tar.gz" ]]; then
        docker exec -i n8n tar xzf - -C / < "$backup_dir/n8n_backup.tar.gz" 2>/dev/null || true
        docker restart n8n
    fi
    
    if [[ -f "$backup_dir/encryption_key.txt" ]]; then
        local enc_key
        enc_key=$(cat "$backup_dir/encryption_key.txt")
        state_set "n8n_encryption_key" "$enc_key"
    fi
    
    log_success "n8n restore complete"
}

restore_grafana() {
    local backup_dir="$1"
    
    log_info "Restoring Grafana from $backup_dir..."
    
    if [[ -d "$backup_dir/provisioning" ]]; then
        cp -r "$backup_dir/provisioning/"* /opt/grafana/provisioning/ 2>/dev/null || true
        docker restart grafana
    fi
    
    log_success "Grafana restore complete"
}

restore_prometheus_stack() {
    local backup_dir="$1"
    
    log_info "Restoring Prometheus stack from $backup_dir..."
    
    if [[ -d "$backup_dir/prometheus_config" ]]; then
        cp -r "$backup_dir/prometheus_config/"* /opt/prometheus/config/ 2>/dev/null || true
        docker restart prometheus
    fi
    
    if [[ -d "$backup_dir/alertmanager_config" ]]; then
        cp -r "$backup_dir/alertmanager_config/"* /opt/alertmanager/config/ 2>/dev/null || true
        docker restart alertmanager
    fi
    
    log_success "Prometheus stack restore complete"
}

restore_samba() {
    local backup_dir="$1"
    
    log_info "Restoring Samba from $backup_dir..."
    
    if [[ -f "$backup_dir/smb.conf" ]]; then
        cp "$backup_dir/smb.conf" /etc/samba/smb.conf
        testparm -s
    fi
    
    if [[ -f "$backup_dir/samba_users.txt" ]]; then
        # Restore users from backup
        while IFS=: read -r user _; do
            [[ -n "$user" ]] && pdbedit -a -u "$user" 2>/dev/null || true
        done < "$backup_dir/samba_users.txt"
    fi
    
    systemctl restart smbd nmbd
    log_success "Samba restore complete"
}

restore_sterling_pdf() {
    local backup_dir="$1"
    
    log_info "Restoring Sterling PDF from $backup_dir..."
    
    if [[ -d "$backup_dir/data" ]]; then
        cp -r "$backup_dir/data/"* /opt/sterling-pdf/data/ 2>/dev/null || true
        docker restart sterling-pdf
    fi
    
    log_success "Sterling PDF restore complete"
}

# ============================================================================
# HIGH-LEVEL BACKUP/RESTORE OPERATIONS
# ============================================================================

# Full system backup
backup_full() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="$BACKUP_ROOT/full-$timestamp"
    
    log_info "Starting full system backup to $backup_dir"
    backup_init
    mkdir -p "$backup_dir"
    backup_manifest_create "$backup_dir"
    
    # Backup configs
    backup_configs "$backup_dir"
    backup_manifest_add_service "$backup_dir" "configs" "completed" '{}'
    
    # Backup Docker volumes
    backup_docker_volumes "$backup_dir"
    backup_manifest_add_service "$backup_dir" "docker_volumes" "completed" '{}'
    
    # Backup databases
    backup_databases "$backup_dir"
    backup_manifest_add_service "$backup_dir" "databases" "completed" '{}'
    
    # Backup individual services
    for svc in ollama pihole n8n grafana prometheus_stack samba sterling_pdf; do
        if config_service_enabled "$svc" 2>/dev/null; then
            log_push_context "backup:$svc"
            local func="backup_$svc"
            if declare -f "$func" >/dev/null; then
                $func "$backup_dir/$svc"
                backup_manifest_add_service "$backup_dir" "$svc" "completed" '{}'
            fi
            log_pop_context
        fi
    done
    
    # Compress full backup
    if [[ "$BACKUP_COMPRESS" == "true" ]]; then
        log_info "Compressing backup..."
        tar czf "$backup_dir.tar.gz" -C "$BACKUP_ROOT" "full-$timestamp"
        rm -rf "$backup_dir"
        backup_dir="$backup_dir.tar.gz"
    fi
    
    log_success "Full backup complete: $backup_dir"
    echo "$backup_dir"
}

# Restore from full backup
restore_full() {
    local backup_path="$1"
    
    [[ -f "$backup_path" || -d "$backup_path" ]] || {
        log_error "Backup not found: $backup_path"
        return 1
    }
    
    local backup_dir="$backup_path"
    
    # Extract if compressed
    if [[ "$backup_path" == *.tar.gz ]]; then
        log_info "Extracting backup..."
        backup_dir="/tmp/initops-restore-$(date +%s)"
        tar xzf "$backup_path" -C /tmp
        backup_dir="$backup_dir/full-*"
        backup_dir=$(echo $backup_dir)
    fi
    
    log_info "Restoring from $backup_dir"
    
    # Verify manifest
    [[ -f "$backup_dir/manifest.json" ]] || {
        log_error "Invalid backup: no manifest"
        return 1
    }
    
    # Restore configs
    log_info "Restoring configurations..."
    [[ -d "$backup_dir/configs" ]] && {
        cp "$backup_dir/configs/initops-state" "$STATE_FILE" 2>/dev/null || true
        cp "$backup_dir/configs/nginx.conf" "/etc/nginx/sites-available/initops" 2>/dev/null || true
        cp "$backup_dir/configs/htpasswd" "/etc/nginx/.htpasswd" 2>/dev/null || true
        cp "$backup_dir/configs/smb.conf" "/etc/samba/smb.conf" 2>/dev/null || true
        nginx -t && systemctl reload nginx 2>/dev/null || true
        testparm -s && systemctl restart smbd nmbd 2>/dev/null || true
    }
    
    # Restore Docker volumes
    log_info "Restoring Docker volumes..."
    if [[ -d "$backup_dir/volumes" ]]; then
        for vol in "$backup_dir/volumes"/*.tar.gz; do
            [[ -f "$vol" ]] || continue
            local name=$(basename "$vol" .tar.gz)
            local target=""
            case "$name" in
                pihole_data) target="/opt/pihole" ;;
                n8n_data) target="/opt/n8n" ;;
                grafana_data) target="/opt/grafana" ;;
                prometheus_data) target="/opt/prometheus" ;;
                alertmanager_data) target="/opt/alertmanager" ;;
                sterling_pdf_data) target="/opt/sterling-pdf" ;;
            esac
            [[ -n "$target" ]] && tar xzf "$vol" -C "$(dirname "$target")" 2>/dev/null || true
        done
    fi
    
    # Restore services
    for svc in ollama pihole n8n grafana prometheus_stack samba sterling_pdf; do
        if [[ -d "$backup_dir/$svc" ]]; then
            log_push_context "restore:$svc"
            local func="restore_$svc"
            if declare -f "$func" >/dev/null; then
                $func "$backup_dir/$svc"
            fi
            log_pop_context
        fi
    done
    
    log_success "Full restore complete"
}

# List available backups
backup_list() {
    log_info "Available backups in $BACKUP_ROOT:"
    ls -lah "$BACKUP_ROOT"/ 2>/dev/null || log_warn "No backups found"
}

# Clean old backups
backup_clean() {
    log_info "Cleaning backups older than $BACKUP_RETENTION_DAYS days..."
    find "$BACKUP_ROOT" -type f -name "*.tar.gz" -mtime +"$BACKUP_RETENTION_DAYS" -delete
    find "$BACKUP_ROOT" -type d -name "full-*" -mtime +"$BACKUP_RETENTION_DAYS" -exec rm -rf {} + 2>/dev/null || true
    find "$BACKUP_ROOT" -type d -name "*-202*" -mtime +"$BACKUP_RETENTION_DAYS" -exec rm -rf {} + 2>/dev/null || true
    log_success "Backup cleanup complete"
}

# ============================================================================
# SCHEDULED BACKUP
# ============================================================================

# Setup automatic daily backup via cron
backup_setup_cron() {
    local cron_file="/etc/cron.d/initops-backup"
    
    cat > "$cron_file" << EOF
# InitOps-Server automatic daily backup
0 2 * * * root /usr/local/bin/initops.sh --backup-full >> /var/log/initops-backup.log 2>&1
0 3 * * 0 root /usr/local/bin/initops.sh --backup-clean >> /var/log/initops-backup.log 2>&1
EOF
    
    log_success "Automatic backup cron job installed"
}