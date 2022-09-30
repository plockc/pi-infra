#!/bin/bash

set -euo pipefail

HELM_VERSION=3.10.0
export KUBECONFIG=~/.kube/config

# init cluster
curl -sfL https://get.k3s.io | sh -

# setup kubeconfig
mkdir -p ~/.kube
sudo k3s kubectl config view --raw > "$KUBECONFIG"
chmod 600 "$KUBECONFIG"

# install helm
curl https://get.helm.sh/helm-v$HELM_VERSION-linux-arm.tar.gz | sudo tar -C /usr/local/bin -zxv --strip-components 1 linux-arm/helm

sudo apt install -y linux-modules-extra-raspi nfs-common open-iscsi util-linux jq

# for https://longhorn.io/kb/troubleshooting-volume-with-multipath/
if ! grep -q blacklist /etc/multipath.conf; then
  sudo sed -i -e '$a blacklist { devnode "^sd[a-z0-9]+" }' /etc/multipath.conf
  sudo systemctl restart multipathd
fi

sudo modprobe iscsi_tcp
sudo systemctl enable iscsid
sudo systemctl start iscsid

helm repo add purelb https://gitlab.com/api/v4/projects/20400619/packages/helm/stable
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm install --create-namespace --namespace=purelb purelb purelb/purelb

helm install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace --set service.ui.type="LoadBalancer"
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

curl -sLS https://get.arkade.dev | sudo sh
