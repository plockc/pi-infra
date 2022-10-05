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
echo Use gw 191.168.8.1 as the nameserver
cat <<EOF > /mnt/etc/resolve.conf
nameserver 192.168.8.1
EOF
```

Setup default user config
```append-file:install.sh
wget -O sdboot/userconf.txt 192.168.8.1/userconf.txt
```

Create a script to configure the freshly installed raspian OS on the SD card
```create-file:configure-os.sh
#!/bin/bash

set -eou pipefail
echo Sync time so can run apt
/usr/lib/systemd/systemd-timesyncd &
sleep 5
kill %1
```

Setup keyboard and locale and timezone
```append-file:configure-os.sh
sed -i -e '/XKBDLAYOUT/s/.*/XKBDLAYOUT="us"/' /etc/default/keyboard
sed -i -e '/XKBDMODEL/s/.*/XKBDMODEL="pc105"/' /etc/default/keyboard
echo "en_US.UTF-8" > /etc/default/locale
ln -fs /usr/share/zoneinfo/US/Pacific /etc/localtime
```

Update package lists and install jq
```append-file:configure-os.sh
echo updating apt package lists
apt update
echo installing packages
apt install -y jq vim
```

Setup ssh for user, note that the image has a "pi" home directory but no pi  user.
The startup one shot systemd server userconf will setup the default user (and leverage the pi
directory)  according to the userconf.txt that we set up.  The default user / group id is 1000.
```append-file:configure-os.sh
echo enabled ssh
systemctl enable ssh

echo Setup ssh keys
mkdir -p /home/pi/.ssh
ssh-keygen -t ed25519 -N "" -f /home/pi/.ssh/id_ed25519
wget -O /home/pi/.ssh/authorized_keys 192.168.8.1/authorized_keys
chmod 600 /home/pi/.ssh/authorized_keys
chown 1000:1000 -R /home/pi
```

Tweak the dhcpcd script to recognize that we have a default hostname and to accept the server configuration for the hostname
```append-file:configure-os.sh
echo Setting up hostname assigned from dhcp
sed -i -e 's/# hostname_fqdn=server/hostname_fqdn=server/' /lib/dhcpcd/dhcpcd-hooks/30-hostname
sed -i -e 's/hostname_default=localhost/hostname_default=raspberrypi/' /lib/dhcpcd/dhcpcd-hooks/30-hostname
```

Grab some scripts for setting up k8s
```append-file:configure-os.sh
```

update kernel commandline, use legacy names for network like eth0, and add cgroups, needed for running containers in kubernetes
```append-file:install.sh
(
  set -euo pipefail
  echo Updating kernel command line for cgroups
  cd /sdboot
  if ! grep cgroup cmdline.txt; then
	sed -i -e 's/$/ cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory/' cmdline.txt
  else
	CGroups already configured
  fi
  echo Updaing kernel command line for legacy interface names
  if ! grep net.ifnames cmdline.txt; then
	sed -i -e 's/$/ net.ifnames=0/' cmdline.txt
  else
	CGroups already configured
  fi
)
```

Run the configure script in a chroot for the freshly installed raspian OS on the SD card
```append-file:install.sh
echo Pulling configure-os script
wget -O /mnt/root/configure-os.sh 192.168.8.1/configure-os.sh
chmod 755 /mnt/root/configure-os.sh

echo Running configure-os script
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
