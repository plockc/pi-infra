# not starting new shell as the dhcp variables are not exported

# can source this in other scripts
set +x
env > /etc/dhcp.env

if [[ "\$1" != "bound" ]]; then
    echo DHCP interface not bound ...
    exit 0
fi
ip addr add \$ip/\$mask dev \$interface
ip route add default via \$router dev \$interface
echo nameserver \$dns > /etc/resolv.conf
echo Networking is configured
if tftp -g -l /root/install.sh -r install.sh \$router 2>/dev/null; then
    chmod 744 /root/install.sh
    echo Install script retrieved
else
    echo No install.sh found
fi
