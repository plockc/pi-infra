#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
if ! ls ~/.ssh/id_*.pub; then
  echo No ssh keys in ~/.ssh
fi

echo "#cloud_config" | tee cloud-init-ssh-authorized-keys.cfg 2>/dev/null
echo "ssh_authorized_keys:" | tee -a cloud-init-ssh.cfg 2>/dev/null
for f in $(ls ~/.ssh/id_*.pub); do
  echo "  - $(cat $f)" | tee -a cloud-init-ssh.cfg 2>/dev/null
done
echo 'runcmd: [ssh-keygen -t ed25519 -N "" -f /home/ubuntu/.ssh/id_ed25519]' > cloud-init-ssh.cfg
