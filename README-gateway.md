## Executing this script

Install rundoc, execute rundoc to extract the script embedded in this README, the run the gateway install script.

```usage
pip3 install rundoc
rundoc run -a README.md
install_os.sh
```


## Header 

If DEVICE is empty, then `install_os.sh` will suggest USB block devices that can be used.  The external device is for the gateway and should have access to the gateway to internet, acceptable values are eth0 and wlan0, eth1 on USB is expected to be the pocket network.

Also make sure we fail on errors.
```bash
#!/bin/bash

set -euo pipefail
```


## Download

Pull ubuntu preinstalled server, which is a compacted complete disk image

```bash
wget --no-clobber http://cdimage.ubuntu.com/releases/18.04.4/release/ubuntu-18.04.4-preinstalled-server-armhf+raspi3.img.xz
```

## Install

Find SD Card (check is for USB devices: not generic, sorry)

```bash
echo Finding SD Card on USB device
if [[ "${DEVICE:-}" == "" ]]; then
    DEVICES="$(ls /sys/bus/usb/devices/*/*/host*/target*/*/block)"
    echo -e "\nFound devices: $DEVICES\n"
    echo -e "usage: env DEVICE=<device name e.g. sdb> $0\n"
    exit 1
fi
```

make sure that device is available but no filesystems are found

```bash
echo Checking for filesystems on $DEVICE
foundParts=$(lsblk -J "/dev/$DEVICE" )
if [[ "$foundParts" == "" ]]; then
    echo Device $DEVICE is not available
    exit 1
fi
foundPartsCount=$(echo "$foundParts" | jq -r ".blockdevices[].children|length")
if [[ "$foundPartsCount" != "0" ]]; then
  echo -e "SD card partition table on $DEVICEneeds clearing:\n$(lsblk --fs /dev/"$DEVICE")"
  if mount | grep -q /dev/$DEVICE; then
      echo Also found mounted filesystems, please unmount
  fi
  echo
  for d in $(lsblk -J /dev/$DEVICE | jq -r ".blockdevices[].children[].name"); do
    if mount | grep -q /dev/$d; then
      echo sudo umount /dev/$d;
    fi;
  done 
  echo -e "sudo dd if=/dev/zero of=\"/dev/$DEVICE\" bs=1M count=5\n" 
  exit 1
fi
```

Unpack ubuntu onto the selected device

```bash
echo Unpacking ubuntu onto SD Card at $DEVICE
xzcat --stdout ubuntu-18.04.4-preinstalled-server-armhf+raspi3.img.xz | pv | sudo dd of=/dev/$DEVICE bs=1M
sudo partprobe
```

Mount the ubuntu partitions

```bash
PIROOT=/media/$USER/piroot
sudo mkdir -p /media/$USER/piboot "$PIROOT"
sudo mount /dev/${DEVICE}1 /media/$USER/piboot
sudo mount /dev/${DEVICE}2 "$PIROOT"
```

## Network Interfaces

Set up interfaces.  `eth0` is connected to external network with DHCP.

```create-file:gateway/eth0.yaml#files
network:
    version: 2
    renderer: networkd
    ethernets:
        eth0:
            dhcp4: true
```

Copy the network files (adjust as needed prior to running install_os.sh)

```bash
pushd "$PIROOT"/etc/netplan
sudo cp ~1/gateway/eth{0,1}.yaml .
popd
```

I think it's to avoid cloud init from conflicting from manual setup of netplan
```create-file:gateway/cloud-init/99-disable-network-config.cfg#files
network: {config: disabled}
```

## SSH

Add ssh keys

```bash
if ! ls ~/.ssh/id_*.pub; then
  echo No ssh keys in ~/.ssh
fi

pushd "$PIROOT"/etc/cloud/cloud.cfg.d
echo "ssh_authorized_keys:" | sudo tee 99-ssh_authorized_keys.cfg 2>/dev/null
for f in $(ls ~/.ssh/id_*.pub); do
  echo "  - $(cat $f)" | sudo tee -a 99-ssh_authorized_keys.cfg 2>/dev/null
done
popd
```

## User

TODO: create user to match `$USER`


## Packages

```create-file:gateway/cloud-init/99-packages.cfg#files
packages:
  - rng-tools
  - python3-pip
```

## Cloud init configuration

Copy the configuration files
```bash
pushd "$PIROOT"/etc/cloud/cloud.cfg.d
sudo cp ~1/gateway/cloud-init/*.cfg .
popd
```

## Copy this project

```bash
git archive --format=tar.gz --prefix=pi-infra/ HEAD | sudo tar -C "$PIROOT"/root/ -x
```

## Complete

Unmount the sd card partitions

```bash
sync
sleep 1
sudo umount /dev/${DEVICE}1 /dev/${DEVICE}2
sudo eject /dev/${DEVICE}

echo Completed!
```

## Serial Console

### Serial Device
Some text says ttyAMA0 would be the serial port on pins 8 and 10 on the pi, however bluetooth on pi3+ used ttyAMA0, and instead serial was moved to ttyS0 unless bluetooth was disabled in boot config `dtoverlay=pi3-disable-bt`.  Ubuntu (20 and 18?) can use serial0 which will pick the right device for you.  

### Kernel Config
Usually with serial console, two entries exist in the kernel command line for "console".  One for serial console with a baud rate, e.g.: `console=serial0,115200`.  Also the console still should go to the normal display device so another entry is for tty1.

### USB 
I paid $11 for 3 pack of EVISWIY PL2303TA USB to TTL Serial Cable, seems to work fine.  the serial port shows up as `/dev/ttyUSB0`.

### Client

(Picocom)[https://github.com/npat-efault/picocom] works well.

To collect the terminal current height and width and then run picocom assuming USB to serial port adapter.

```
tput cols
tput lines
sudo picocom -b 115200 /dev/ttyUSB0
```

Set the terminal height and width with the values collected above
```
stty rows 24 cols 80
```

Exit session with `Ctrl-a Ctrl-x`

## Notes

Manually update network interface configuration by editing files in `/etc/netplan`

```
sudo netplan generate
sudo netplan apply
```

## Troubleshooting

- 7 green blinks mean kernel is not found
- ubuntu kernel probably has some of the support as modules and needs matching initramfs
- if the screen scales to a higher resolution and becomes blurry (cheap 5" screens off of amazon), set framebuffer_width and framebuffer_height in config.txt for the actual hardware

## Further Reading

https://www.raspberrypi.org/documentation/configuration/config-txt/README.md
