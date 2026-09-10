#!/usr/bin/env bats

# BATS tests for InitOps-Server

load 'test_helper'

@test "initops.sh exists and is executable" {
    [ -x "${PROJECT_ROOT}/initops.sh" ]
}

@test "initops.sh shows help" {
    run "${PROJECT_ROOT}/initops.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "initops.sh shows version" {
    run "${PROJECT_ROOT}/initops.sh" --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ "InitOps-Server" ]]
}

@test "initops.sh generates config template" {
    run "${PROJECT_ROOT}/initops.sh" --generate-config
    [ "$status" -eq 0 ]
    [[ "$output" =~ "vpn:" ]]
    [[ "$output" =~ "ollama:" ]]
    [[ "$output" =~ "services:" ]]
}

@test "lib/core.sh exists" {
    [ -f "${PROJECT_ROOT}/lib/core.sh" ]
}

@test "lib/vpn.sh exists" {
    [ -f "${PROJECT_ROOT}/lib/vpn.sh" ]
}

@test "lib/docker.sh exists" {
    [ -f "${PROJECT_ROOT}/lib/docker.sh" ]
}

@test "lib/ollama.sh exists" {
    [ -f "${PROJECT_ROOT}/lib/ollama.sh" ]
}

@test "lib/nginx.sh exists" {
    [ -f "${PROJECT_ROOT}/lib/nginx.sh" ]
}

@test "lib/services/raspap.sh exists" {
    [ -f "${PROJECT_ROOT}/lib/services/raspap.sh" ]
}

@test "lib/services/pihole.sh exists" {
    [ -f "${PROJECT_ROOT}/lib/services/pihole.sh" ]
}

@test "lib/services/n8n.sh exists" {
    [ -f "${PROJECT_ROOT}/lib/services/n8n.sh" ]
}

@test "lib/services/samba.sh exists" {
    [ -f "${PROJECT_ROOT}/lib/services/samba.sh" ]
}

@test "lib/services/sterling-pdf.sh exists" {
    [ -f "${PROJECT_ROOT}/lib/services/sterling-pdf.sh" ]
}

@test "lib/services/cockpit.sh exists" {
    [ -f "${PROJECT_ROOT}/lib/services/cockpit.sh" ]
}

@test "lib/services/grafana.sh exists" {
    [ -f "${PROJECT_ROOT}/lib/services/grafana.sh" ]
}

@test "config/default.yaml exists" {
    [ -f "${PROJECT_ROOT}/config/default.yaml" ]
}

@test "config/examples/pi.yaml exists" {
    [ -f "${PROJECT_ROOT}/config/examples/pi.yaml" ]
}

@test "config/examples/server.yaml exists" {
    [ -f "${PROJECT_ROOT}/config/examples/server.yaml" ]
}

@test "config/examples/minimal.yaml exists" {
    [ -f "${PROJECT_ROOT}/config/examples/minimal.yaml" ]
}