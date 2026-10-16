#!/usr/bin/env bash
set -Eeuo pipefail

LAB=/mnt/raid-lab
RAID_UUID="$(cat "$LAB/raid.uuid")"

LOOP1="$(losetup -fP --nooverlap --show "$LAB/disk1.img")"
LOOP2="$(losetup -fP --nooverlap --show "$LAB/disk2.img")"
LOOP3="$(losetup -fP --nooverlap --show "$LAB/disk3.img")"

printf 'RAID devices: %s %s; LVM device: %s\n' "$LOOP1" "$LOOP2" "$LOOP3"

udevadm settle --timeout=10

if ! blkid -U "$RAID_UUID" >/dev/null 2>&1; then
    mdadm --assemble --scan --config="$LAB/raid.conf"
    udevadm settle --timeout=10
fi

mkdir -p /mnt/raid /mnt/logs
if ! mountpoint -q /mnt/raid; then
    mount -U "$RAID_UUID" /mnt/raid
fi

pvscan --cache "$LOOP3"
vgchange -ay vg_data
udevadm settle --timeout=10

if ! mountpoint -q /mnt/logs; then
    mount /dev/vg_data/lv_logs /mnt/logs
fi
