#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
if ! ls ~/.ssh/id_*.pub; then
  echo No ssh keys in ~/.ssh
fi

ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519

echo "ssh_authorized_keys:" | tee cloud-init-ssh-authorized-keys.cfg 2>/dev/null
for f in $(ls ~/.ssh/id_*.pub); do
  echo "  - $(cat $f)" | tee -a cloud-init-ssh-authorized-keys.cfg 2>/dev/null
done
