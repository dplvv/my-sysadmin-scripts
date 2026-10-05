#!/usr/bin/env bash
set -Eeuo pipefail

INTERVAL=5

# Проверяем наличие необходимых команд.
for cmd in date free df uptime sleep dirname touch; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        printf 'Error: required command is missing: %s\n' "$cmd" >&2
        exit 1
    fi
done

# Лог располагается рядом со скриптом.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/monitor.log"

# Проверяем возможность записи в обычный файл.
if ! touch -- "$LOG_FILE" || [[ ! -f "$LOG_FILE" || ! -w "$LOG_FILE" ]]; then
    printf 'Error: cannot write to log file: %s\n' "$LOG_FILE" >&2
    exit 1
fi

trap 'printf "Error: monitoring failed at line %s\n" "$LINENO" >&2' ERR
trap 'printf "\nMonitoring stopped.\n"; exit 0' INT TERM

printf 'Monitoring every %s seconds. Log: %s\n' "$INTERVAL" "$LOG_FILE"
printf 'Press Ctrl+C to stop.\n'

while true; do
    {
        printf -- '--- %s ---\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"

        printf '[free -h]\n'
        free -h

        printf '\n[df -h]\n'
        df -h

        printf '\n[uptime]\n'
        uptime

        printf '\n'
    } >> "$LOG_FILE"

    sleep "$INTERVAL"
done
