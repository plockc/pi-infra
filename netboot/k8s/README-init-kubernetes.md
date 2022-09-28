```create-file:init-kubernetes.sh
#!/bin/bash

set -euo pipefail

ARCADE_VERSION=0.8.45
HELM_VERSION=3.10.0
export KUBECONFIG=~/.kube/config

# init cluster
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=servicelb" sh -

# install arcade
curl -sSL https://github.com/alexellis/arkade/releases/download/${ARCADE_VERSION}/arkade-arm64
sudo mv arkade-arm64 /usr/local/bin/arkade
sudo ln -s  /usr/local/bin/ark{ade,}

# metallb does not currently support arm64
# https://github.com/bitnami/charts/issues/7305


# setup kubeconfig
mkdir -p ~/.kube
sudo k3s kubectl config view --raw > "$KUBECONFIG"
chmod 600 "$KUBECONFIG"
echo "export KUBECONFIG=~/.kube/config" >> ~/.profile

# needed to find where the linux modules package is located
sudo apt install -y nfs-common open-iscsi util-linux

sudo modprobe iscsi_tcp
sudo systemctl enable iscsid
sudo systemctl start iscsid

# install helm
curl https://get.helm.sh/helm-v$HELM_VERSION-linux-arm.tar.gz | sudo tar -C /usr/local/bin -zxv --strip-components 1 linux-arm/helm

# for https://longhorn.io/kb/troubleshooting-volume-with-multipath/
if ! grep -q blacklist /etc/multipath.conf; then
  sudo sed -i -e '$a blacklist { devnode "^sd[a-z0-9]+" }' /etc/multipath.conf
  sudo systemctl restart multipathd
fi

helm repo add longhorn https://charts.longhorn.io
helm repo update
helm install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace --set service.ui.type="LoadBalancer"
```
