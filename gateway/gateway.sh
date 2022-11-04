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
