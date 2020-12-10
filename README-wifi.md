```env
WIFI_SSID=
WIFI_PASSWORD=
```

Wireless network

```r-create-file:gateway/wlan0.yaml#files
network:
    version: 2
    renderer: networkd
    wifis:
        wlan0:
            # allow OS to start (while still building boot sequeuence)
            optional: true
            # do not release IP address
            critical: true
            dhcp4: true
            access-points:
                "%:WIFI_SSID:%":
                    password: "%:WIFI_PASSWORD:%"
```

```bash
pushd "$PIROOT"/etc/netplan
sudo cp ~1/gateway/wlan0.yaml .
popd
```
