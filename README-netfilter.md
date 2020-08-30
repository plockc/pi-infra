# Experimental

# IP Router Firewall

It is expected that there is a VLAN aware network switch that attaches to this router, the upstream internet gateway, and all southbound network devices.

The Netgear GS308E is a cheap switch that has all the needed management, accessible by web browser.

There are some opinionated conventions the scripts below will obey, to avoid so many variables.

VLAN 1 will be traffic that can reach the internet through the upstream gateway
VLAN 2 will be traffic that will go through this netfilter

The northbound internet gateway will be attached to the first port:
* only a member of VLAN 1
* untagged to the gateway (to simplify gateway configuration)
* pvid 1, other devices have to be member of VLAN 1 to bypass this netfilter and communicate directly with the internet
* IP will be 192.168.1.1/24

This router will be attached with to port 2:
* pvid vlan 1 to that eth0 can reach the internet
* member of VLAN 2 with tagged traffic so the filter sees VLAN 2
* member of VLAN 1 with untagged traffic so the filter sees internet traffic on eth0
* IP will be 192.168.1.2/24 for eth0, and 192.168.2.1/24 for VLAN2 subinterface

Other ports normally will be untagged ports so the attached device thinks their connection is normal, but for them to be filtered through this device, their pvid needs to be VLAN 2.

This configuration will NAT northbound (towards default gateway) traffic.  New connections destined for this host is firewalled except for basic ping and ssh, but outbound from this host is open.  Filtering will block new and existing connections inbound and outbound, otherwise it will forward all packets to the upstream gateway, and forward return traffic from the upstream gateway only for established connections.  New connections inbound will be blocked.

Filtering is based on resolving a list of hostnames from a config file.  The set of resolved IPs for each host expires after 5 minutes, and the config file is checked for updates every 30 seconds.  An iptables ipset is updated if the list of IPs has changed.  Problems with lookups will eventually not filter traffic.  

## Configuration

The northbound gateway
```env
GATEWAY=192.168.1.1
```

## Enable Forwarding

Normally linux drops traffic if neither the source or destination is this box, so enable forwarding:
```bash
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.d/99-ip-forwarding.conf
```

## Creating the rules.v4 file

Install iptables-persistent, which will read `/etc/iptables/rules.v{4,6}` to initialize iptables on start.
```bash
sudo apt-get install -y iptables-persistent ipset
```

Create rules.v4
```
rundoc run README-iptables.md
```

## IPV4
Default packet filtering policy is to DROP packets coming in to this host or forwarded, but outgoing connectivity is normally not blocked.

### Traffic destined to host

#### Default Policies
```create-file:rules.v4
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
```

#### Always allowed traffic
Allow SSH
```append-file:rules.v4
-A INPUT -p tcp --dport 22 -j ACCEPT
```

Allow ping for this host (request is type 8, response is type 0)
```append-file:rules.v4
-A INPUT -p icmp -m icmp --icmp-type 8 -j ACCEPT
-A INPUT -p icmp -m icmp --icmp-type 0 -j ACCEPT
```

Accept any incoming connections that were already established
```append-file:rules.v4
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
```

Allow any traffic to loopback device
```append-file:rules.v4
-A INPUT -i lo -j ACCEPT
```

#### Explicit Rejected Traffic
Drop invalid packets
```append-file:rules.v4
-A INPUT -m conntrack --ctstate INVALID -j DROP
```

Some ICMP messages for rejected packets
```append-file:rules.v4
-A INPUT -p udp -j REJECT --reject-with icmp-port-unreachable
-A INPUT -p tcp -j REJECT --reject-with tcp-reset
-A INPUT -j REJECT --reject-with icmp-proto-unreachable
```


### Traffic forwarded (src and dest are both not this host)

#### Filtered Traffic

Create the ipsets used for remote services to be filtered
```bash
sudo ipset create gaming-servers hash:ip -exist timeout 90 
sudo ipset create video-servers hash:ip -exist timeout 90
```

Create the ipsets used for local hosts to be filtered
```bash
sudo ipset create gaming-clients hash:ip -exist 
sudo ipset create video-clients hash:ip -exist
```

Mark any packets that belong to the client sets
```r-append-file:rules.v4
-A FORWARD -m set --match-set gaming-clients src,dst -j MARK --set-xmark 0x1/0x0
-A FORWARD -m set --match-set video-clients src,dst -j MARK --set-xmark 0x2/0x0
```

Block clients from servers
```r-append-file:rules.v4
-A FORWARD -m set --match-set gaming-servers dst,src -m mark --mark 0x1 -j DROP
```

#### Allowed Traffic

Forward any traffic outbound to gateway
```r-append-file:rules.v4
-A FORWARD --destination %:GATEWAY:% -j ACCEPT
```

Forward any packets on already established connections
```append-file:rules.v4
-A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
```

Forward packets for explicitly allowed services, such as `ssh` port and ICMP for `ping`
```append-file:rules.v4
-A FORWARD -p tcp --dport 22 -j ACCEPT
-A FORWARD -p icmp -m icmp --icmp-type 8 -j ACCEPT
-A FORWARD -p icmp -m icmp --icmp-type 0 -j ACCEPT
```

Commit the changes
```append-file:rules.v4
COMMIT
```

### NAT outbound traffic

Default is to not NAT traffic
```append-file:rules.v4
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
```

NAT traffic routed to the gateway, as gw doesn't have route back to filtered hosts
```r-append-file:rules.v4
-A POSTROUTING --destination %:GATEWAY:% -j MASQUERADE
```

Commit the changes
```append-file:rules.v4
COMMIT
```

### Rest of tables no-op
Reset all the other tables
```append-file:rules.v4
*raw
:PREROUTING ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
COMMIT

*security
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
COMMIT

*mangle
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
COMMIT
```

## Block IPv6

Just block all ipv6
```create-file:rules.v6
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT DROP [0:0]
COMMIT

*raw
:PREROUTING DROP [0:0]
:OUTPUT DROP [0:0]
COMMIT

*nat
:PREROUTING DROP [0:0]
:INPUT DROP [0:0]
:OUTPUT DROP [0:0]
:POSTROUTING DROP [0:0]
COMMIT

*security
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT DROP [0:0]
COMMIT

*mangle
:PREROUTING DROP [0:0]
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT DROP [0:0]
:POSTROUTING DROP [0:0]
COMMIT
```

Check that the rules are valid
```bash
sudo iptables-restore -t rules.v4
sudo ip6tables-restore -t rules.v6
```

Load the rules (ubuntu specific service name)
```
sudo service netfilter-persistent reload
```

