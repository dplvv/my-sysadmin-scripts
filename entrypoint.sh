#!/usr/bin/env bash
set -Eeuo pipefail

/usr/local/bin/script.sh &
monitor_pid=$!

python3 -u -m http.server 8080 --bind 0.0.0.0 --directory /var/www &
http_pid=$!

cleanup() {
    trap - EXIT INT TERM
    kill -TERM "$monitor_pid" "$http_pid" 2>/dev/null || true
    wait "$monitor_pid" "$http_pid" 2>/dev/null || true
}

trap cleanup EXIT
trap 'exit 0' INT TERM

wait -n "$monitor_pid" "$http_pid"
