These scripts are switching over to raspian as the kernel is more stable and the OS is a little simpler.  Initially only the netboot install is raspian.  Lessons learned on how to netboot ubuntu are included here.

### Firmware

Raspian has the boot firmware in /boot, while ubuntu has it in /boot/firmware

### DHCP Hostname Configuration

post-dhcp-configured script to be run on the installed system, can be tested with `systemctl renew eth0` and checked with `systemctl status networkd-dispatcher` and link info with `networkctl status`.

Some info: [network-dispatcher](https://gitlab.com/craftyguy/networkd-dispatcher#usage)

This file needs to be placed in /etc/networkd-dispatcher/configured.d (the configured.d dir will need to be created), and made executable

```create-file:networkd-dispatcher-hostname.sh
#!/bin/bash
# Created by README-netboot.md

for addr in $IP_ADDRS; do
if host $addr > /dev/null; then
        new_name=$(host $addr 192.168.8.1 | grep " domain name pointer " | sed 's/.* \(.*\)\.$/\1/')
        if [ "$new_name" != "" ]; then
                echo $new_name > /etc/hostname
                hostname $new_name
                echo "Updated hostname to $new_name"
        fi
fi
done
```

### Disable cloud-init

Run ubuntu server configuration that has to happen post boot using cloud-init runcmd, then add an entry to disable cloud-init on subsequent boots to keep things like hostname or resolv.conf from being updated:

Place in /etc/cloud/cloud.cfg.d/99-configure-system.cfg
```
runcmd:
  - touch /etc/cloud/cloud-init.disabled
  - systemctl reboot
```

