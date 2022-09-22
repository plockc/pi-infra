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

```env
DEVICE=sda
NEW_HOSTNAME=unnamed
```

## Install

```create-file:install-sd.sh
#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
. download-ubuntu.sh
. verify-device.sh
. unpack-ubuntu-onto-device.sh
. cloud-init-ssh.sh
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
. vars.sh
FILE=ubuntu-${UBUNTU_VERSION}.${UBUNTU_PATCH_VERSION}-preinstalled-server-armhf+raspi.img.xz
if [ ! -e $FILE ]; then
    wget --no-clobber http://cdimage.ubuntu.com/releases/${UBUNTU_VERSION}/release/$FILE
fi
```

### Verify SD Card

Find SD Card (check is for USB devices: not generic, sorry), and verify no filesystems are on the card.

```r-create-file:verify-device.sh
#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
. vars.sh
if [[ "%:DEVICE:%" == "" ]]; then
    DEVICES="$(ls /sys/bus/usb/devices/*/*/host*/target*/*/block)"
    echo -e "\nFound devices: $DEVICES\n"
    echo -e "usage: env DEVICE=<device name e.g. sdb> $0\n"
    exit 1
fi

foundParts=$(lsblk -J "/dev/%:DEVICE:%" )
if [[ "$foundParts" == "" ]]; then
    echo Device %:DEVICE:% is not available
    exit 1
fi

foundPartsCount=$(echo "$foundParts" | jq -r ".blockdevices[].children|length")
if [[ "$foundPartsCount" != "0" ]]; then
  echo -e "Found filesystems, please umount filesystems and clear SD card partition table:\n$(lsblk --fs /dev/%:DEVICE:%)"
  echo -e "\nThis command will wipe the partition table:"
  echo -e "sudo dd if=/dev/zero of=\"/dev/%:DEVICE:%\" bs=1M count=5\n" 
  exit 1
fi
```

## Install and Mount Ubuntu on SD Card

Unpack ubuntu onto the selected device

```r-create-file:unpack-ubuntu-onto-device.sh
#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail

. vars.sh
FILE=ubuntu-${UBUNTU_VERSION}.${UBUNTU_PATCH_VERSION}-preinstalled-server-armhf+raspi.img.xz
xzcat --stdout $FILE | pv | sudo dd of=/dev/%:DEVICE:% bs=1M
sudo partprobe
```

Mount the boot and root ubuntu partitions from the device
```r-create-file:mount-ubuntu-from-device.sh
#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
. vars.sh

PIROOT=/media/$USER/piroot
sudo mkdir -p /media/$USER/piboot "$PIROOT"
sudo mount /dev/%:DEVICE:%1 /media/$USER/piboot
sudo mount /dev/%:DEVICE:%2 "$PIROOT"
```

## Networking Cloud-init config

Set up interfaces. `eth0` is connected to external network.

Interface for external network as DHCP
```create-file:sd-card-eth0.yaml
# created by README-install-ubuntu-on-sd-card.md
network:
    version: 2
    #renderer: networkd
    ethernets:
        eth0:
            optional: true
            dhcp4: true
            # do not release IP address
            critical: true
            link-local: [ipv4]
```

Wireless network, assumes that vars.sh was updated with WIFI SSID and password.

```r-create-file:sd-card-wlan0.yaml#template-with-vars
# created by README-install-ubuntu-on-sd-card.md
network:
    version: 2
    #renderer: networkd
    wifis:
        wlan0:
            # allow OS to start (while still building boot sequeuence)
            optional: true
            # do not release IP address
            critical: true
            dhcp4: true
            access-points:
                "%:WIFI_SSID:%":
                    password: "%:WIFI_PASSWORD:%"
```

Avoid cloud init from conflicting from our manual setup of netplan
```create-file:cloud-init-disable-network-config.cfg
# created by README-install-ubuntu-on-sd-card.md
network: {config: disabled}
```

Set the hostname

```r-create-file:sd-card-hostname#template-with-vars
# created by README-install-ubuntu-on-sd-card.md
%:NEW_HOSTNAME:%
```

## SSH

Add ssh keys to a cloud init configuration file

```create-file:cloud-init-ssh.sh
#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
if ! ls ~/.ssh/id_*.pub; then
  echo No ssh keys in ~/.ssh
fi

echo "#cloud_config" | tee cloud-init-ssh-authorized-keys.cfg 2>/dev/null
echo "ssh_authorized_keys:" | tee -a cloud-init-ssh.cfg 2>/dev/null
for f in $(ls ~/.ssh/id_*.pub); do
  echo "  - $(cat $f)" | tee -a cloud-init-ssh.cfg 2>/dev/null
done
echo 'runcmd: [ssh-keygen -t ed25519 -N "" -f /home/ubuntu/.ssh/id_ed25519]' > cloud-init-ssh.cfg
```

## Copy Configuration

Copy the configuration files and update kernel command line to use legacy interface names
```r-create-file:apply-config-to-sd-card.sh
#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
. vars.sh

PIROOT=/media/$USER/piroot

pushd "$PIROOT"/etc/cloud/cloud.cfg.d
sudo cp ~1/cloud-init-ssh.cfg 99-ssh.cfg
sudo cp ~1/cloud-init-disable-network-config.cfg 99-disable-network-config.cfg
popd

sudo cp sd-card-hostname /etc/hostname

pushd "$PIROOT"/etc
if [[ "${WIFI_SSID:-}" != "" ]]; then
    sudo cp sd-card-wlan0.yaml /etc/netplan/
fi
sudo cp ~1/sd-card-eth0.yaml netplan/
popd

if [ ! grep ifnames /media/$USER/piboot ]; then
  sed -i -e 's/$/ net.ifnames=0/' /media/$USER/piboot
fi


```


## Complete

Unmount the sd card partitions

```r-create-file:unmount.sh
#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
. vars.sh

sync
sudo umount /dev/%:DEVICE:%1 /dev/%:DEVICE:%2
sudo eject /dev/%:DEVICE:%

echo Completed!
```

Rerun rundoc but with vars.sh for tagged templates
```
#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
. vars.sh

rundoc run -t template-with-vars README-install-ubuntu-on-sd-card.md
```

## Troubleshooting

- 7 green blinks mean kernel is not found
- ubuntu kernel probably has some of the support as modules and needs matching initramfs
