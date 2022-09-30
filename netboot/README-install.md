# Install script

This script is run on the pi being netbooted, it will pull an OS image, then unpack it onto the disk.

It is called by init2 (which is on the initrams).

This script is run from init2 on the netbooted initramfs.


# Configuration

```env
UBUNTU_VERSION=22.04.1
```

# Load dhcp values

Start with bash header, load DHCP configured values, and figure out the OS image
```r-create-file:install.sh
#!/bin/ash

set -euo pipefail

if [ ! -e /dev/mmcblk0 ]; then
	echo Missing SD Card, cannot install
	exit 1
fi

echo RUNNING INSTALL
echo ---------------

echo Loading values determined by dhcp
source /etc/dhcp.env

if cat /proc/cpuinfo | grep Model | grep -q "Pi 4"; then
	set -x
	PLATFORM=arm64
	set +x
else
	set -x
	PLATFORM=armhf
	set +x
fi

set -x
IMAGE=ubuntu-%:UBUNTU_VERSION:%-preinstalled-server-${PLATFORM}+raspi.img.xz
set +x

```

Pull the image from tftp, the router address comes from dhcp.env
```append-file:install.sh
echo Download OS Image
wget ${router}/$IMAGE
```

Write the image to disk then mount the partitions
```append-file:install.sh

echo Writing image to System SD Card
xzcat $IMAGE | pv | dd of=/dev/mmcblk0 bs=1M
```

Verify the partitions
```append-file:install.sh
echo Detecting partitions
partprobe /dev/mmcblk0

echo Mounting partitions
mkdir -p /mnt
mkdir -p sdboot
mount /dev/mmcblk0p1 sdboot
mount /dev/mmcblk0p2 /mnt
```

Stop cloud init configuration
TODO: create separate script so can run outside of cloud init
```append-file:install.sh
cat <<EOF > /mnt/etc/cloud/cloud.cfg.d/99-configure-system.cfg
runcmd:
  - bash /root/configure-os.sh
  - systemctl reboot
EOF
```

This script will do some OS level work prior to a reboot
```append-file:configure-os.sh
#!/bin/bash
# created by README-install.sh

set -euo pipefail

mkdir -p /home/ubuntu/.ssh
ssh-keygen -t ed25519 -N "" -f /home/ubuntu/.ssh/id_ed25519
chown ubuntu:ubuntu /home/ubuntu/.ssh/id_ed25519{,.pub}
wget -O /home/ubuntu/.ssh/authorized_keys 192.168.8.1/authorized_keys
chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys
chmod 600 /home/ubuntu/.ssh/authorized_keys
apt update
apt install -y jq
if ! modprobe iscsi_tcp; then
    apt install -y linux-modules-extra-raspi
fi
if [ -d /etc/cloud ]; then
    touch /etc/cloud/cloud-init.disabled
fi
if [ -f /lib/dhcpcd/dhcpcd-hooks/30-hostname ]; then
    sudo sed -i -e 's/# hostname_fqdn=server/hostname_fqdn=server/' /lib/dhcpcd/dhcpcd-hooks/30-hostname
    sudo sed -i -e 's/hostname_default=localhost/hostname_default=raspberrypi/' /lib/dhcpcd/dhcpcd-hooks/30-hostname
fi
```

if dhclient were being used, then this script could update the hostname based on the DHCP hostname sent if placed in /etc/dhcp/dhclient-exit-hooks.d/hostname, however systemd-networkd uses it's own client.  You can `sudo dhclient -r eth0` to remove lease then `sudo dhclient -d eth0` to test (ctrl-c to exit the foreground process).
Note: this script is not used, it's just for documentation.
```append-file:dhclient-hostname.sh
case "$reason" in
    BOUND | RENEW | REBOOT | REBIND)
        hostname $new_host_name
        echo $new_host_name > /etc/hostname
    ;;
esac
```

Setup post dhcp configured script for setting hostname
```append-file:install.sh
mkdir /mnt/etc/networkd-dispatcher/configured.d

(
  set -euo pipefail
  cd /mnt/etc/networkd-dispatcher/configured.d
  wget -O hostname ${router}/networkd-dispatcher-hostname.sh
  chmod 755 hostname
)

```

update kernel commandline, use legacy names for network like eth0, and add cgroups, needed for running containers in kubernetes
```append-file:configure-os.sh
(
  set -euo pipefail
  if [ -f /boot/cmdline.txt ]; then
    cd /boot
  elif [ -f /boot/firmware/cmdline.txt ]; then
    cd /boot/firmware
  fi
  if ! grep cgroup cmdline.txt; then
	sudo sed -i -e 's/$/ net.ifnames=0 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory/' cmdline.txt
  else
	CGroups already configured
  fi
)
```

Clean up and end the installation
```append-file:install.sh
echo Sync-ing disks
sync

echo Unmounting partitions
umount sdboot /mnt

echo Successful Installation
```
