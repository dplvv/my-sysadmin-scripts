#!/usr/bin/env bash

INTERVAL=5

while true; do
    {
        printf -- '--- %s ---\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        free -h
        df -h
        uptime
        printf '\n'
    } >> monitor.log

    sleep "$INTERVAL"
done
