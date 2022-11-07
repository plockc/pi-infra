# pi-infra

WARNING: this is pre-alpha work, I use it, but every time I use it I tweak something and I don't do e2e testing when I make changes.  Also, there are some leftovers at the top directory level.  Consider this a collection of ideas on how to make things work and will probably need little adjustments to actually work.  It's also confusing the environment/context the code runs in, sorry about that.

The most important files in this repo are the READMEs that document the scripts and processes to build a very opinionated home infrastructure based on raspberry pis, with aspirations to include netboot and a kubernetes cluster.

Each README has snippets of scripts and files that a special utility `rundoc` can extract from the README that documents the script.

## Required Hardware

- An ubuntu machine to install gateway to SD card, this can be an extra raspberry pi to act as a build node, although the local machine will need basic things like SSH.
- rapsberry pi 3 or 4 to act as gateway router and provide netboot services
- a set of raspberry pi 4 to be k8s nodes
- sd cards for each pi without partition tables (unbootable)
- switch for pocket network (one port for each pi, port for gateway, and an uplink port if not using wifi), and a port for build node if not using a local machine
- USB ethernet adapter (ubuntu compatible)
- Something to see console on nodes
  - USB to TTL cable for serial console
  - Extra monitor is useful, including portable like 5” 800x480 portal display

## Documentation

https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#raspberry-pi-4-boot-flow

## Executing this script

```
pip3 -u install rundoc
~/.config/local/bin/rundoc run -a README.md
./gateway.sh
```

## Operating Systems

- ubuntu preinstalled server - will be the OS for the gatway and base for Kubernetes nodes

## Software

- rundoc will process the READMEs to generate the scripts and code
- dnsmasq provides DNS, tftp, and DHCP on the gateway
- custom scripts will be run on build node, and on the gateway to provide netboot services and boot images

## Overview

An Ubuntu "build node" will be designated to create the gateway (which is a firewall, eventually a caching proxy server, and eventually netboot).  This build node can be built as part of this process.

The build node will install ubuntu onto an SD card for the gateway, mount the partitions, update the configuration, then eject the sd card for installation into a raspberry pi to be the gateway.

Raspberry Pi4s have to have eeprom configured to netboot as secondary to sdcard.

The gateway boots and starts dnsmasq.

First raspi master is net booted which runs a custom installer for ubuntu, then installs images for kubernetes, then reboots and inits a cluster using kubeadm.

The cluster token is acquired and configured, then the remaining raspis are netbooted also installing ubuntu and kubernetes images, then reboots and then joins the cluster using kubeadm.

## Lack of Security

The cluster depends on physical security.  Later upgrades will focus on encrypted disk and intervention to decrypt on boot (which later can be helped via serial port access)

## Network

All of the networks here are considered pocket (non-routed), the external network is determined by DHCP and outbound traffic will be NAT-ed.

Pi node network: 192.168.8.0/24
kubernetes service network: 192.168.10.0/23
kubernetes pod network: 192.168.12.0/23
kubernetes external service network: 192.168.14.0/23

internal gateway & DNS: 192.168.8.1
gateway hostname: gw
build node: build-node
domain for internal network: k8s.local

k3os hostnames (`cp` control node, `w` worker node): `{cp,w}[0-9]+`

## Script Generation

The env below will be used to template `gateway/vars.sh` which will be sourced by `gateway.sh`.  For details of the content of these values, see [README-gateway.sh](gREADME-gateway.sh).

```env
DEVICE=
EXTERNAL_DEVICE=eth0
WIFI_SSID=CONFIGURE_SSID
WIFI_PASSWORD=CONFIGURE_PASSWORD
```

This will extract `gateway.sh` from `README-gateway.md`.

```bash
rundoc list-blocks README-gateway.md -t bash | jq -r '.code_blocks[] | .code' > gateway.sh
rundoc run README-gateway.md -t files
chmod 755 gateway.sh
```
