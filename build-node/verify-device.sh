#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
. vars.sh
if [[ "sda" == "" ]]; then
    DEVICES="$(ls /sys/bus/usb/devices/*/*/host*/target*/*/block)"
    echo -e "\nFound devices: $DEVICES\n"
    echo -e "usage: env DEVICE=<device name e.g. sdb> $0\n"
    exit 1
fi

foundParts=$(lsblk -J "/dev/sda" )
if [[ "$foundParts" == "" ]]; then
    echo Device sda is not available
    exit 1
fi

foundPartsCount=$(echo "$foundParts" | jq -r ".blockdevices[].children|length")
if [[ "$foundPartsCount" != "0" ]]; then
  echo -e "Found filesystems, please umount filesystems and clear SD card partition table:\n$(lsblk --fs /dev/sda)"
  echo -e "\nThis command will wipe the partition table:"
  echo -e "sudo dd if=/dev/zero of=\"/dev/sda\" bs=1M count=5\n" 
  exit 1
fi
