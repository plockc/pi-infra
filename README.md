# pi-infra
home infrastructure based on raspberry pi, including netboot and kubernetes cluster

## Hardware

- Desktop UNIX to install gateway to SD card
- rapsberry pi 3 or 4 to act as gateway router and provide netboot services
- a set of raspberry pi 4 to be k8s nodes
- sd cards for each pi without partition tables (unbootable)
- 4+ port switch for pocket network (one port for each pi)
- USB ethernet adapter (ubuntu compatible)
- Something to see console
  - USB to TTL cable for serial console
  - Extra monitor, including portable like 5” 800x480 portal display

## Operating Systems

- k3os dedicates the OS as a kubernetes master or worker node
- ubuntu preinstalled server - will be the OS for the gatway and as a bootable base for a k3os overlay filesystem

## Software

- rundoc will process the READMEs to generate the scripts and code
- dnsmasq provides DNS, tftp, and DHCP on the gateway
- custom scripts will be run on desktop, and the gateway

## Overview

The desktop will install ubuntu onto the gateway, mount the partitions, update the configuration, then eject the sd card for installation into a raspberry pi to be the gateway.

Raspberry Pi4s have to have eeprom configured to netboot as secondary to sdcard.

The gateway boots and starts dnsmasq.

First raspi master is booted which runs a custom installer for ubuntu then overlay k3os, then reboots and establishes a cluster.

The cluster token is acquired and configured, then the remaining raspis are booted also installing ubuntu and verlay k3os then reboots and the new node joins the cluster.

## Lack of Security

The cluster depends on physical security.  Later upgrades will focus on encrypted disk and intervention to decrypt on boot (which later can be helped via serial port access)

## Network

not routed / pocket ip range: 192.168.3.0/24
pocket network gateway & DNS: 192.168.3.1
gateway hostname: infra1

k3os hostnames (`m` master, `w` worker): `pik8s{m,w}[0-9]+`

## Script Generation

```bash
rundoc list-blocks README-gateway.md -t bash | jq -r '.code_blocks[] | .code' > gateway.sh
rundoc run README-gateway.md -t files
chmod 755 gateway.sh
```
