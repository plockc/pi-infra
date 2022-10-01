Not used, but if dhclient was used ...

called by dhclient, this script can update the hostname based on the DHCP hostname sent if placed in /etc/dhcp/dhclient-exit-hooks.d/hostname  You can `sudo dhclient -r eth0` to remove lease then `sudo dhclient -d eth0` to test (ctrl-c to exit the foreground process).

```create-file:dhclient-hostname.sh
case "$reason" in
    BOUND | RENEW | REBOOT | REBIND)
        hostname $new_host_name
        echo $new_host_name > /etc/hostname
    ;;
esac
```

