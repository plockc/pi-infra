```create-file:kubernetes-prep.sh
#!/bin/bash

set -euo pipefail

# install arcade
if ! which ark; then
    curl -sLS https://get.arkade.dev | sudo sh
    echo 'export PATH="$PATH":~/.arkade/bin' > ~/.profile
    source ~/.profile
fi

ark get helm
ark get nerdctl

sudo apt install -y nfs-common open-iscsi util-linux jq

sudo modprobe iscsi_tcp
sudo systemctl enable iscsid
sudo systemctl start iscsid
```
