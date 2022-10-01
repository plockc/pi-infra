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
IMAGE=2022-09-22-raspios-bullseye-${PLATFORM}-lite.img.xz
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

Setup nameserver
```append-file:install.sh
cat <<EOF > /mnt/etc/resolve.conf
nameserver 192.168.8.1
EOF
```

Create a script to configure the freshly installed raspian OS on the SD card
```create-file:configure-os.sh
#!/bin/bash

set -eou pipefail
mount -t proc proc /proc
/usr/lib/systemd/systemd-timesyncd &
```

Update package lists and install jq
```append-file:configure-os.sh
apt update
apt install -y jq
```

Setup ssh for user
```append-file:configure-os.sh
mkdir -p /home/ubuntu/.ssh
ssh-keygen -t ed25519 -N "" -f /home/ubuntu/.ssh/id_ed25519
wget -O /home/ubuntu/.ssh/authorized_keys 192.168.8.1/authorized_keys
chmod 600 /home/ubuntu/.ssh/authorized_keys
```

Tweak the dhcpcd script to recognize that we have a default hostname and to accept the server configuration for the hostname
```append-file:configure-os.sh
sudo sed -i -e 's/# hostname_fqdn=server/hostname_fqdn=server/' /lib/dhcpcd/dhcpcd-hooks/30-hostname
sudo sed -i -e 's/hostname_default=localhost/hostname_default=raspberrypi/' /lib/dhcpcd/dhcpcd-hooks/30-hostname
```

update kernel commandline, use legacy names for network like eth0, and add cgroups, needed for running containers in kubernetes
```append-file:install.sh
(
  set -euo pipefail
  cd /sdboot
  if ! grep cgroup cmdline.txt; then
	sudo sed -i -e 's/$/ cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory/' cmdline.txt
  else
	CGroups already configured
  fi
  if ! grep net.ifnames cmdline.txt; then
	sudo sed -i -e 's/$/ net.ifnames=0/' cmdline.txt
  else
	CGroups already configured
  fi
)
```

Run the configure script in a chroot for the freshly installed raspian OS on the SD card
```append-file:install.sh
wget -O /mnt/root/configure-os.sh 192.168.8.1/configure-os.sh
chroot /mnt /root/configure-os.sh
```

Clean up and end the installation
```append-file:install.sh
echo Sync-ing disks
sync

echo Unmounting partitions
umount sdboot /mnt

echo Successful Installation
```
