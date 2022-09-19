#!/bin/bash
# created by README-build-node.md
set -euo pipefail
if [[ "${DEVICE:-}" == "" ]]; then
    DEVICES="$(ls /sys/bus/usb/devices/*/*/host*/target*/*/block)"
    echo -e "\nFound devices: $DEVICES\n"
    echo -e "usage: env DEVICE=<device name e.g. sdb> $0\n"
    exit 1
fi

foundParts=$(lsblk -J "/dev/$DEVICE" )
if [[ "$foundParts" == "" ]]; then
    echo Device $DEVICE is not available
    exit 1
fi

foundPartsCount=$(echo "$foundParts" | jq -r ".blockdevices[].children|length")
if [[ "$foundPartsCount" != "0" ]]; then
  echo -e "Found filesystems, please umount filesystems and clear SD card partition table:\n$(lsblk --fs /dev/"$DEVICE")"
  echo -e "\nThis command will wipe the partition table:"
  echo -e "sudo dd if=/dev/zero of=\"/dev/$DEVICE\" bs=1M count=5\n" 
  exit 1
fi
