#!/usr/bin/env bash
# Ollama module for InitOps-Server
# Hardware-aware model selection and deployment

install_ollama() {
    local model="${1:-auto}"
    local use_gpu="${2:-true}"

    if state_is_done "ollama"; then
        log_info "Ollama already installed, skipping"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would install Ollama with model: ${model}"
        state_mark_done "ollama"
        return 0
    fi

    log_info "Installing Ollama..."

    # Install Ollama
    curl -fsSL https://ollama.ai/install.sh | bash

    # Enable and start service
    systemctl enable --now ollama

    # Wait for service to be ready
    sleep 5
    wait_for_port "localhost" 11434 30

    # Determine model to use
    local selected_model
    selected_model=$(select_ollama_model "${model}" "${use_gpu}")

    log_info "Pulling model: ${selected_model}"
    ollama pull "${selected_model}"

    log_success "Ollama installed with model: ${selected_model}"
    log_info "API available at: http://localhost:11434"

    state_mark_done "ollama"
}

select_ollama_model() {
    local requested_model="$1"
    local use_gpu="$2"

    # If specific model requested, use it
    if [[ "${requested_model}" != "auto" ]]; then
        echo "${requested_model}"
        return 0
    fi

    # Auto-select based on hardware
    local ram_gb
    ram_gb=$(get_total_ram_gb)
    local has_gpu_flag=false
    [[ "${use_gpu}" == "true" ]] && has_gpu_flag=$(has_gpu && echo true || echo false)

    log_info "Hardware detected: ${ram_gb}GB RAM, GPU: ${has_gpu_flag}"

    # Model selection based on RAM and GPU
    if [[ ${ram_gb} -lt 4 ]]; then
        echo "tinyllama:1.1b"
    elif [[ ${ram_gb} -lt 8 ]]; then
        echo "llama3.2:3b"
    elif [[ ${ram_gb} -lt 16 ]]; then
        if [[ "${has_gpu_flag}" == "true" ]]; then
            echo "llama3.1:8b"
        else
            echo "llama3.2:3b"
        fi
    elif [[ ${ram_gb} -lt 32 ]]; then
        if [[ "${has_gpu_flag}" == "true" ]]; then
            echo "llama3.1:8b"
        else
            echo "llama3.1:8b"
        fi
    else
        if [[ "${has_gpu_flag}" == "true" ]]; then
            echo "llama3.1:70b-q4_K_M"
        else
            echo "llama3.1:8b"
        fi
    fi
}

configure_ollama_gpu() {
    local gpu_vendor
    gpu_vendor=$(get_gpu_vendor)

    case "${gpu_vendor}" in
        nvidia)
            log_info "Configuring Ollama for NVIDIA GPU..."
            # Ensure nvidia-container-toolkit is installed
            if ! command -v nvidia-smi &>/dev/null; then
                log_warn "NVIDIA drivers not found, GPU acceleration may not work"
            fi
            ;;
        amd)
            log_info "Configuring Ollama for AMD GPU (ROCm)..."
            ;;
        intel)
            log_info "Configuring Ollama for Intel GPU..."
            ;;
        *)
            log_info "No supported GPU detected, using CPU inference"
            ;;
    esac
}