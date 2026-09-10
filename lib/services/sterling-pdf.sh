#!/usr/bin/env bash
# Sterling PDF service module for InitOps-Server
# Web-based PDF toolkit (merge, split, convert, sign, OCR)

install_sterling_pdf() {
    if state_is_done "sterling_pdf"; then
        log_info "Sterling PDF already installed, skipping"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would install Sterling PDF via Docker"
        state_mark_done "sterling_pdf"
        return 0
    fi

    log_info "Installing Sterling PDF..."

    # Ensure Docker is installed
    if ! command -v docker &>/dev/null; then
        install_docker
    fi

    # Create Sterling PDF directories
    mkdir -p /opt/sterling-pdf/data /opt/sterling-pdf/logs

    # Pull Sterling PDF image
    pull_docker_image "frooodle/s-pdf:latest"

    # Run Sterling PDF container
    docker run -d \
        --name sterling-pdf \
        --restart unless-stopped \
        -p 3001:8080 \
        -e DOCKER_ENABLE_SECURITY=false \
        -e INSTALL_BOOK_AND_ADVANCED_OPERATIONS=true \
        -v /opt/sterling-pdf/data:/usr/share/nginx/html/data \
        -v /opt/sterling-pdf/logs:/var/log/nginx \
        frooodle/s-pdf:latest

    # Wait for Sterling PDF to be ready
    sleep 10
    wait_for_port "localhost" 3001 60

    log_success "Sterling PDF installed"
    log_info "Access Sterling PDF at: http://$(get_primary_ip):3001"
    log_info "Available via nginx at: https://$(get_primary_ip)/pdf/"

    state_mark_done "sterling_pdf"
}

configure_sterling_pdf() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would configure Sterling PDF"
        return 0
    fi

    log_info "Sterling PDF configuration complete (via environment variables)"
    log_info "Features enabled: Book operations, Advanced operations, Security disabled for local use"
}