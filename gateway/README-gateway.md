# Configure SD Card as Gateway

This sets up the gateway (with NAT) for a firewalled pocket network using dnsmasq for DNS and DHCP and updates it's hostname.

Scripts generated from this rundoc need to be run on the gateway, though can be generated elsewhere, such as on the build node.

Set up interfaces.  `eth0` is connected to external network, while the pocket network will be on USB on `eth1`, raspberry pi 4 would have much better network speeds than earlier versions over USB (~300Mbit for USB 3.0).

The faster connection is used for external network to allow for the gateway to also be used as home internet gateway.

## Executing this script

Install rundoc, execute rundoc to extract the script embedded in this README, edit configuration in vars.sh, the run the gateway install script.

```usage
pip3 install rundoc
rundoc run README-gateway.md
bash gateway.sh
```

## Network Interfaces

USB dongle Ethernet for internal network, it's assumed that eth0 and wlan are already created.
```create-file:gateway/eth1.yaml#files
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

```bash
sudo cp eth1.yaml /etc/netplan/
```

## Hostname resolution

Set the hostname

```create-file:gateway-hostname
gw
```

Turn off systemd DNS stub so dnsmasq can listen 
```create-file:gateway-resolved.conf
echo DNSStubListener=no
```

## Install Packages

```create-file:gateway-packages.sh
sudo apt install -y dnsmasq rng-tools iptables-persistent netfilter-persistent
```

## IP Forwarding

This is not firewalling, it's just forwarding packets with NAT currently.

NAT the forwarded packets that go to external networks
```create-file:gateway-rules.v4#files
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

Copy the configuration files to mounted ubuntu filesystem, enable forwarding, and have iptables configuration loaded on startup.
```create-file:apply-gateway-config.sh
pushd /etc
sudo cp ~1/gateway/resolved.conf systemd/resolved.conf
sudo cp ~1/gateway/cloud-init/sd-card-hostname hostname
echo "net.ipv4.ip_forward = 1" > sysctl.conf.d/99-enabled-fowarding.conf
sudo mkdir -p iptables
sudo cp ~1/gateway-rules.v4 iptables/rules.v4
popd
```


## dnsmasq

DNS and DHCP will be configured on eth1 for the pocket network, and provide a DNS server on eth0 and wlan0 to optionally provide DNS for the external network.

```create-file:gateway-dnsmasq-pocket.conf
listen-address=192.168.8.1
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
dhcp-range=192.168.3.100,192.168.3.250,100d
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
```

```create-file:gateway-dnsmasq-hosts
192.168.8.1 gw
```

```create-file:gateway-dnsmasq-resolv.conf
nameserver 1.1.1.1
options edns0
search k8s.local
```

Copy the configuration files
```bash
pushd /etc
sudo cp ~1/gateway-dnsmasq-pocket.conf dnsmasq.d/pocket
sudo cp ~1/gateway-dnsmasq-hosts hosts.dnsmasq
sudo cp ~1/gateway-dnsmasq-resolv.conf resolv.dnsmasq.conf
popd
```


