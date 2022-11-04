# Configure SD Card as Gateway

This sets up the gateway (with NAT) for a firewalled pocket network using dnsmasq for DNS and DHCP and updates it's hostname.

Scripts and files generated from this rundoc need to be *copied and run on the gateway*, though can be generated elsewhere, such as on the build node.

Set up interfaces. `eth1` is connected to external network with USB Ethernet device, while the pocket network will be on primary interface on `eth0`, which may require moving the primary cable.  note raspberry pi 4 would have much better network speeds than earlier versions over USB.

The upstream is lower throughtput on a pi4 due to USB limits, though if your upstream (internet) connection is 500Mbit/s or less, this will not matter.  The faster LAN connection can also help serving cached assets.

## Executing this script

Install rundoc, execute rundoc with the init tag to extract the scripts and config files embedded in this README, the run the gateway install script.

```
pip3 install rundoc
rundoc run README-gateway.md
bash gateway.sh 
```

Add envionment variables to change networks and hostname, etc. and add the init tag to rundoc to allow for calculations.  The defaults are below:

```env#go
DHCP_CIDR=192.168.8.0/21
GW_HOSTNAME=gw
DOMAIN=lan
RANGE_PERCENT_DHCP=75
```

These are calculated from environment inputs

```env#init#go
GW_ADDR=192.168.8.1
DHCP_START=192.168.10.0
DHCP_END=192.168.15.254
```

Example:

```
DHCP_CIDR=192.168.3.0/24 GW_HOSTNAME=router rundoc run --inherit-env -t init README-gateway.md
```

Running gateway.sh will run a series of scripts:

```create-file:gateway.sh#go
#!/bin/bash
# created by README-gateway.md
set -euo pipefail

. packages.sh
. apply-gateway-config.sh
. dnsmasq.sh

echo =============================================================================
echo Swap cables so upstream is on USB, and downstream is connected directly to Pi
echo And Then `sudo systemctl reboot`
echo =============================================================================
```

## Network Interfaces

Ethernet for internal network.
```r-create-file:eth0.yaml#go
# created by README-gateway.md
network:
    version: 2
    renderer: networkd
    ethernets:
        eth0:
            optional: true
            dhcp4: false
            addresses: [%:GW_ADDR:%/%:DHCP_CIDR_SIZE:%]
            # no gateway, we don't want this host to route over the pocket
            nameservers:
                    search: [%:DOMAIN:%]
                    addresses: [%:GW_ADDR:%, 1.1.1.1]
```

For external network on USB

```create-file:eth1.yaml#go
# created by README-gateway.md
network:
    version: 2
    renderer: networkd
    ethernets:
        eth1:
            optional: false
            # pick up DNS entries
            dhcp4: true
            # do not release IP address on shutdown
            critical: true
            link-local: [ipv4]
```


## Hostname resolution

Set the hostname

```create-file:hostname#go
gw
```

Turn off systemd DNS stub so dnsmasq can listen 
```create-file:disable-stub-listener.conf#go
[Resolve]
DNSStubListener=no
```

## Install Packages

```create-file:packages.sh#go
#!/bin/bash
# created by README-gateway.md
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo apt install -y rng-tools iptables-persistent netfilter-persistent net-tools prips dnsmasq
```

## IP Forwarding

This is not firewalling, it's just forwarding packets northbound with NAT currently.  Do not use this machine as an internet gateway, have a hardened machine upstream (dd-wrt / openwrt / ISP provided router)

NAT the forwarded packets that go to external networks
```create-file:rules.v4#go
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
-A POSTROUTING -o eth1 -j MASQUERADE -m comment --comment "NAT northbound traffic"
-A POSTROUTING -o wlan0 -j MASQUERADE -m comment --comment "NAT northbound traffic"
COMMIT
```


## Apply Configuration

Copy the configuration files to mounted ubuntu filesystem, enable forwarding, and have iptables configuration loaded on startup.
```r-create-file:apply-gateway-config.sh#go
#!/bin/bash
# created by README-gateway.md
set -euo pipefail

sudo hostname %:GW_HOSTNAME:%
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-enabled-fowarding.conf > /dev/null
pushd /etc
sudo cp ~1/eth0.yaml ~1/eth1.yaml netplan/
sudo cp ~1/hostname hostname
sudo mkdir -p iptables
sudo cp ~1/rules.v4 iptables/
popd
```

## dnsmasq

DNS and DHCP will be configured on eth1 for the pocket network, and provide a DNS server on eth0 and wlan0 to optionally provide DNS for the external network.

```r-create-file:dnsmasq-pocket.conf#go
# default is 150
cache-size=1000
no-dhcp-interface=eth1
no-dhcp-interface=wlan0
# static route
dhcp-option=121,0.0.0.0/0,%:GW_ADDR:%
dhcp-range=%:DHCP_START:%,%:DHCP_END:%,20m
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
domain=%:DOMAIN:%
```

```r-create-file:dnsmasq-hosts#go
%:GW_ADDR:% %:GW_HOSTNAME:%
```

```create-file:dnsmasq-resolv.conf#go
nameserver 1.1.1.1
options edns0
```

Copy the configuration files. Install dnsmasq, it will fail to start as systemd-resolved is still running.

Restart systemd-resolved to read in the disable configuration for the Stub listener.

Restart dnsmasq to re-attempt binding.

```create-file:dnsmasq.sh#go
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

# will stop hostname resolution
sudo systemctl restart systemd-resolved
# will restore hostname resolution
sudo systemctl restart dnsmasq
# fix local host name resolution
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf > /dev/null
```

This section will calculate some additional environment and Re-run this rundoc with computed variables if user did not specify the 'init' tag

```bash#init
set -euo pipefail

export DHCP_CIDR_SIZE=$(cut -f 2 -d / <<<"${DHCP_CIDR}")
echo We have a /${DHCP_CIDR_SIZE} network
numIPs=$(prips ${DHCP_CIDR} | wc -l)
echo With $numIPs IPs
startOff=$(($numIPs*(100-${RANGE_PERCENT_DHCP})/100))
export GW_ADDR=$(prips $DHCP_CIDR | sed -n "2p")
echo Gateway is $GW_ADDR
export DHCP_START=$(prips ${DHCP_CIDR} | sed -n "${startOff}p")
export DHCP_END=$(prips ${DHCP_CIDR} | sed -n "$((numIPs-1))p")
echo DHCP range is $DHCP_START - $DHCP_END

bash -c 'rundoc run --inherit-env -t go -N init README-gateway.md'
```
