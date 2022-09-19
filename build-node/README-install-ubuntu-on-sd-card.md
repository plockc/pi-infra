# Configure SD Card as Ubuntu

This installs Ubuntu onto SD Card.

## Executing this script

Execute rundoc to extract the script embedded in this README, edit configuration in vars.sh, then run the install script.

```
pip3 install --user rundoc
rundoc run -a README-install-ubuntu-on-sd-card.md
bash install-sd.sh
```

## Variables 

These vars can be edited in install-vars.sh, they will be included by other scripts
If DEVICE is empty, then `verify-device.sh` will suggest USB block devices that can be used.

Note: This file will be overwritten when rerunning rundoc.

```r-create-file:install-vars.sh#files
DEVICE=sda
WIFI_SSID=
WIFI_PASSWORD=
UBUNTU_VERSION=22.04
UBUNTU_PATCH_VERSION=1
```

## Install

```create-file:install-sd.sh
#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
. download-ubuntu.sh
. verify-device.sh
. unpack-ubuntu-onto-device.sh
. mount-ubuntu-from-device.sh
. apply-config-to-sd-card.sh
. unmount.sh
```

### Download

Pull ubuntu preinstalled server, which is a compacted complete disk image

```create-file:download-ubuntu.sh
#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
. install-vars.sh
FILE=ubuntu-${UBUNTU_VERSION}.${UBUNTU_PATCH_VERSION}-preinstalled-desktop-arm64+raspi.img.xz
if [ ! -e $FILE ]; then
    wget --no-clobber http://cdimage.ubuntu.com/releases/${UBUNTU_VERSION}/release/$FILE
fi
```

### Verify SD Card

Find SD Card (check is for USB devices: not generic, sorry), and verify no filesystems are on the card.

```create-file:verify-device.sh
#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
. install-vars.sh
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
```

## Install and Mount Ubuntu on SD Card

Unpack ubuntu onto the selected device

```create-file:unpack-ubuntu-onto-device.sh
#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
. install-vars.sh

xzcat --stdout ubuntu-18.04.4-preinstalled-server-armhf+raspi3.img.xz | pv | sudo dd of=/dev/$DEVICE bs=1M
sudo partprobe
```

Mount the boot and root ubuntu partitions from the device
```create-file:mount-ubuntu-from-device.sh
#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
. install-vars.sh

PIROOT=/media/$USER/piroot
sudo mkdir -p /media/$USER/piboot "$PIROOT"
sudo mount /dev/${DEVICE}1 /media/$USER/piboot
sudo mount /dev/${DEVICE}2 "$PIROOT"
```

## Networking Cloud-init config

Set up interfaces. `eth0` is connected to external network.

Interface for external network as DHCP
```create-file:eth0.yaml
network:
    version: 2
    renderer: networkd
    ethernets:
        eth1:
            optional: true
            dhcp4: true
            # do not release IP address
            critical: true
            link-local: [ipv4]
```

Avoid cloud init from conflicting from our manual setup of netplan
```create-file:cloud-init-disable-network-config.cfg
network: {config: disabled}
```

Set the cloud-init hostname

```create-file:cloud-init-gw-hostname.cfg
hostname: gw
```

Turn off systemd DNS stub so dnsmasq can listen 
```create-file:resolved.conf
echo DNSStubListener=no
```

## SSH

Add ssh keys to a cloud init configuration file

```create-file:cloud-init-ssh-authorized-keys.cfg
#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
if ! ls ~/.ssh/id_*.pub; then
  echo No ssh keys in ~/.ssh
fi

pushd build-node
echo "ssh_authorized_keys:" | tee ssh_authorized_keys.cfg 2>/dev/null
for f in $(ls ~/.ssh/id_*.pub); do
  echo "  - $(cat $f)" | tee -a ssh_authorized_keys.cfg 2>/dev/null
done
popd
```

## Copy Configuration

Copy the configuration files
```create-file:apply-config-to-sd-card.sh
#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail

PIROOT=/media/$USER/piroot

pushd "$PIROOT"/etc/cloud/cloud.cfg.d
sudo cp ~1/cloud-init-ssh_authorized_keys.cfg 99-ssh_authorized_keys.cfg
sudo cp ~1/cloud-init-disable-network-config.cfg 99-disable-network-config.cfg
sudo cp ~1/cloud-init-gw-hostname 99-hostname.cfg
popd

pushd "$PIROOT"/etc
sudo cp ~1/eth0.yaml netplan/
sudo cp ~1/resolved.conf systemd/
popd
```


## Complete

Unmount the sd card partitions

```r-create-file:unmount.sh
#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
. install-vars.sh

sync
sudo umount /dev/${DEVICE}1 /dev/${DEVICE}2
sudo eject /dev/${DEVICE}

echo Completed!
```

## Troubleshooting

- 7 green blinks mean kernel is not found
- ubuntu kernel probably has some of the support as modules and needs matching initramfs
