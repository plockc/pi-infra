# IP Router Firewall

This will NAT northbound (towards default gateway) traffic.  New connections destined for this host is firewalled except for basic ping and ssh, outbound is open.  It will forward anything to the upstream gateway, and forward return traffic from the upstream gateway for established connections.

## Configuration

The northbound gateway

```env
GATEWAY=
```

## Creating the rules.v4 file

Install iptables-persistent
```
sudo apt-get install -y iptables-persistent
```

Ubuntu on start will read `/etc/iptables/rules.v{4,6}` to initialize iptables on start.

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

Allow ping (request is type 8, response is type 0)
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


### Traffic forwarded (src and dest are both external)

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

NAT traffic routed to the gateway
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
