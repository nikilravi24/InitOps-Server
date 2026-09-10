#!/usr/bin/env bash

# BATS test helper

export PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="${PROJECT_ROOT}:${PATH}"

# Mock functions for testing
mock_apt() {
    return 0
}

mock_systemctl() {
    return 0
}

mock_docker() {
    return 0
}