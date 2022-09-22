# Configure SD Card as Gateway

This sets up the gateway (with NAT) for a firewalled pocket network using dnsmasq for DNS and DHCP and updates it's hostname.

Scripts generated from this rundoc need to be run on the gateway, though can be generated elsewhere, such as on the build node.

Set up interfaces.  `eth0` is connected to external network, while the pocket network will be on USB on `eth1`, raspberry pi 4 would have much better network speeds than earlier versions over USB (~300Mbit for USB 3.0).

The faster connection is used for external network to allow for the gateway to also be used as home internet gateway.

## Executing this script

Install rundoc, execute rundoc to extract the script embedded in this README, edit configuration in vars.sh, the run the gateway install script.

```
pip3 install rundoc
rundoc run README-gateway.md
bash gateway.sh
```

Running gateway.sh will run a series of scripts:
```create-file:gateway.sh
#!/bin/bash
# created by README-gateway.md
set -euo pipefail

. packages.sh
. darkhttpd.sh
. apply-gateway-config.sh
. dnsmasq.sh
```

## Network Interfaces

USB dongle Ethernet for internal network, it's assumed that eth0 and wlan are already created.
```create-file:eth1.yaml
# created by README-gateway.md
network:
    version: 2
    renderer: networkd
    ethernets:
        eth1:
            optional: true
            dhcp4: false
            addresses: [192.168.8.1/24]
            # no gateway, we don't want this host to route over the pocket
            nameservers:
                    search: [k8s.local]
                    addresses: [192.168.8.1, 1.1.1.1]
```

Copy the network files (adjust as needed prior to running gateway.sh)

## Hostname resolution

Set the hostname

```create-file:hostname
gw
```

Turn off systemd DNS stub so dnsmasq can listen 
```create-file:disable-stub-listener.conf
[Resolve]
DNSStubListener=no
```

## Install Packages

```create-file:packages.sh
#!/bin/bash
# created by README-gateway.md
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo apt install -y rng-tools iptables-persistent netfilter-persistent
```

## IP Forwarding

This is not firewalling, it's just forwarding packets with NAT currently.

NAT the forwarded packets that go to external networks
```create-file:rules.v4
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
COMMIT
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -o eth0 -j MASQUERADE
-A POSTROUTING -o wlan0 -j MASQUERADE
COMMIT
```

## HTTPD Server

Compile the server
```create-file:darkhttpd.sh
wget https://raw.githubusercontent.com/emikulic/darkhttpd/master/darkhttpd.c
gcc --static -O darkhttpd.c -o darkhttpd
```

Create the systemd service file so it runs on startup and restarts if a failure.
```create-file:darkhttpd.service
[Unit]
Description=Darkhttpd Web Server for /tftpboot
After=network.target

[Service]
Type=simple
ExecStart=/sbin/darkhttpd /tftpboot --addr 192.168.8.1
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
```

## Apply Configuration

Copy the configuration files to mounted ubuntu filesystem, enable forwarding, and have iptables configuration loaded on startup.
```create-file:apply-gateway-config.sh
#!/bin/bash
# created by README-gateway.md
set -euo pipefail

sudo hostname gw
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-enabled-fowarding.conf > /dev/null
pushd /etc
sudo cp ~1/eth1.yaml netplan/
sudo cp ~1/hostname hostname
sudo mkdir -p iptables
sudo cp ~1/rules.v4 iptables/
popd

sudo cp darkhttpd /sbin/
sudo cp darkhttpd.service /etc/systemd/system
sudo systemctl daemon-reload
sudo systemctl enable darkhttpd
sudo systemctl start darkhttpd
```

## dnsmasq

DNS and DHCP will be configured on eth1 for the pocket network, and provide a DNS server on eth0 and wlan0 to optionally provide DNS for the external network.

```create-file:dnsmasq-pocket.conf
# default is 150
cache-size=1000
no-dhcp-interface=eth0
no-dhcp-interface=wlan0
# sets the default route address for DHCP clients, the router will answer
#dhcp-option=option:router,0.0.0.0
# give this IP as the DNS server
#dhcp-option=6,192.168.8.1
# static route
dhcp-option=121,0.0.0.0/0,192.168.8.1
dhcp-range=192.168.8.100,192.168.8.250,100d
log-dhcp
# do not forward requests for non-routed IPs
bogus-priv
# require a domain name before forwarding requests
domain-needed
# have a special resolve configuration that dnsmasq uses
# which allows dnsmasq to use external network dns
# as local system is pointing to dnsmasq
resolv-file=/etc/resolv.dnsmasq.conf
addn-hosts=/etc/hosts.dnsmasq

# for netboot and tftp
domain=k8s.local
enable-tftp
tftp-root=/tftpboot
pxe-service=0,"Raspberry Pi Boot   "
```

```create-file:dnsmasq-hosts
192.168.8.1 gw
```

```create-file:dnsmasq-resolv.conf
nameserver 1.1.1.1
options edns0
#search k8s.local
```

Copy the configuration files. Install dnsmasq, it will fail to start as systemd-resolved is still running.

Restart systemd-resolved to read in the disable configuration for the Stub listener.

Restart dnsmasq to re-attempt binding.

```create-file:dnsmasq.sh
#!/bin/bash
# created by README-gateway.md
set -euo pipefail

pushd /etc
sudo mkdir -p systemd/resolved.conf.d
sudo cp ~1/disable-stub-listener.conf systemd/resolved.conf.d
sudo cp ~1/dnsmasq-pocket.conf dnsmasq.d/pocket
sudo cp ~1/dnsmasq-hosts hosts.dnsmasq
sudo cp ~1/dnsmasq-resolv.conf resolv.dnsmasq.conf
popd

# 
sudo apt install -y dnsmasq
# will stop hostname resolution
sudo systemctl restart systemd-resolved
# will restore hostname resolution
sudo systemctl restart dnsmasq
sudo rm /etc/resolve.conf
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf > /dev/null
```
