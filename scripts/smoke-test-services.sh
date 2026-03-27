#!/bin/bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ./scripts/smoke-test-services.sh <vm|production>

Runs a small set of HTTP and TCP health checks against the current homelab entrypoints.
EOF
}

curl_extra_args=()

if [[ $# -ne 1 ]]; then
    usage
    exit 1
fi

target="$1"

case "$target" in
    vm)
        insecure=(-k)
        homepage_url="https://local.hobitin.eu:8443/"
        grafana_url="https://grafana.local.hobitin.eu:8443/login"
        metrics_url="https://metrics.local.hobitin.eu:8443/health"
        loki_url="https://logs.local.hobitin.eu:8443/ready"
        zigbee_url="https://zigbee.frame1.hobitin.eu:8443/"
        homeassistant_url="https://home.frame1.hobitin.eu:8443/"
        curl_extra_args=(
            --resolve "local.hobitin.eu:8443:127.0.0.1"
            --resolve "grafana.local.hobitin.eu:8443:127.0.0.1"
            --resolve "metrics.local.hobitin.eu:8443:127.0.0.1"
            --resolve "logs.local.hobitin.eu:8443:127.0.0.1"
            --resolve "zigbee.frame1.hobitin.eu:8443:127.0.0.1"
            --resolve "home.frame1.hobitin.eu:8443:127.0.0.1"
        )
        mqtt_host="localhost"
        mqtt_port="8883"
        ;;
    production)
        insecure=()
        homepage_url="https://frame1.hobitin.eu/"
        grafana_url="https://grafana.frame1.hobitin.eu/login"
        metrics_url="https://metrics.frame1.hobitin.eu/health"
        loki_url="https://logs.local.hobitin.eu/ready"
        zigbee_url="https://zigbee.frame1.hobitin.eu/"
        homeassistant_url="https://home.frame1.hobitin.eu/"
        mqtt_host="mqtt.frame1.hobitin.eu"
        mqtt_port="8883"
        ;;
    *)
        usage
        exit 1
        ;;
esac

check_http() {
    local name="$1"
    local url="$2"

    echo "==> $name"
    curl --fail --silent --show-error --location "${insecure[@]}" "${curl_extra_args[@]}" "$url" > /dev/null
}

check_tcp() {
    local name="$1"
    local host="$2"
    local port="$3"

    echo "==> $name"
    nc -z "$host" "$port"
}

echo "Running smoke tests for: $target"

check_http "Homepage" "$homepage_url"
check_http "Grafana" "$grafana_url"
check_http "VictoriaMetrics" "$metrics_url"
check_http "Loki" "$loki_url"
check_http "Zigbee2MQTT" "$zigbee_url"
check_http "Home Assistant" "$homeassistant_url"
check_tcp "MQTT TLS listener" "$mqtt_host" "$mqtt_port"

echo "All smoke tests passed for: $target"
