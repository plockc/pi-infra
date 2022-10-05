```create-file:init-kubernetes.sh
#!/bin/bash

set -euo pipefail

export KUBECONFIG=~/.kube/config

# init cluster
# metallb does not currently support arm64
# https://github.com/bitnami/charts/issues/7305
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=servicelb --cluster-init  --etcd-arg=experimental-apply-warning-duration=300" sh -

#ark install kubectl

# setup kubeconfig
mkdir -p ~/.kube
sudo k3s kubectl config view --raw > "$KUBECONFIG"
chmod 600 "$KUBECONFIG"
echo "export KUBECONFIG=~/.kube/config" >> ~/.profile
source ~/.profile

sudo apt install -y nfs-common open-iscsi util-linux jq

sudo modprobe iscsi_tcp
sudo systemctl enable iscsid
sudo systemctl start iscsid

# install helm
#curl https://get.helm.sh/helm-v$HELM_VERSION-linux-arm.tar.gz | sudo tar -C /usr/local/bin -zxv --strip-components 1 linux-arm/helm

# for https://longhorn.io/kb/troubleshooting-volume-with-multipath/
if ! grep -q blacklist /etc/multipath.conf; then
  sudo sed -i -e '$a blacklist { devnode "^sd[a-z0-9]+" }' /etc/multipath.conf
  sudo systemctl restart multipathd
fi

helm repo add purelb https://gitlab.com/api/v4/projects/20400619/packages/helm/stable
helm repo add longhorn https://charts.longhorn.io
helm repo update

helm install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace --set service.ui.type="LoadBalancer"
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

helm install --create-namespace --namespace=purelb purelb purelb/purelb
```

On the gateway, add iptables rule for ingress
```
rule="PREROUTING --table nat --protocol tcp -i eth0 --dport 80 --jump DNAT --to-destination 192.168.14.10:80"
if ! sudo iptables -C $rule ; then
  sudo iptables --append $rule
fi
```

Then add host entries on mac at /private/etc/hosts and clean dns cache
```
sudo killall -HUP mDNSResponder
```

---

I ended up switching traefik to insecure and also removing the entrypoint spec from the dashboard ingressroute to get it to work

and set up argo insecure
```
ubuntu@cp1:~ $ kubectl get -o yaml -n argocd cm argocd-cmd-params-cm
...
apiVersion: v1
data:
  server.insecure: "true"
...
```

```
apiVersion: v1
items:
- apiVersion: traefik.containo.us/v1alpha1
  kind: IngressRoute
  metadata:
    annotations:
      helm.sh/hook: post-install,post-upgrade
    creationTimestamp: "2022-09-28T05:14:53Z"
    generation: 2
    labels:
      app.kubernetes.io/instance: traefik
      app.kubernetes.io/managed-by: Helm
      app.kubernetes.io/name: traefik
      helm.sh/chart: traefik-10.19.300
    name: traefik-dashboard
    namespace: kube-system
    resourceVersion: "584108"
    uid: d9354765-4bc7-48b0-b553-a897372b11c2
  spec:
    routes:
    - kind: Rule
      match: Host(`traefik.k8s.local`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))
      services:
      - kind: TraefikService
        name: api@internal
kind: List
metadata:
  resourceVersion: ""
```

```
apiVersion: v1
items:
- apiVersion: traefik.containo.us/v1alpha1
  kind: IngressRoute
  metadata:
    annotations:
      kubectl.kubernetes.io/last-applied-configuration: |
        {"apiVersion":"traefik.containo.us/v1alpha1","kind":"IngressRoute","metadata":{"annotations":{},"name":"argocd-server","namespace":"argocd"},"spec":{"entryPoints":["websecure"],"routes":[{"kind":"Rule","match":"Host(`argocd.example.com`)","priority":10,"services":[{"name":"argocd-server","port":80}]},{"kind":"Rule","match":"Host(`argocd.example.com`) \u0026\u0026 Headers(`Content-Type`, `application/grpc`)","priority":11,"services":[{"name":"argocd-server","port":80,"scheme":"h2c"}]}],"tls":{"certResolver":"default"}}}
    creationTimestamp: "2022-10-05T00:16:49Z"
    generation: 3
    name: argocd-server
    namespace: argocd
    resourceVersion: "586393"
    uid: 4f267a41-0c2b-4c3c-82a3-0627b1f73301
  spec:
    entryPoints:
    - web
    routes:
    - kind: Rule
      match: Host(`argo.k8s.local`)
      priority: 10
      services:
      - name: argocd-server
        port: 80
    - kind: Rule
      match: Host(`argo.k8s.local`) && Headers(`Content-Type`, `application/grpc`)
      priority: 11
      services:
      - name: argocd-server
        port: 80
        scheme: h2c
kind: List
metadata:
  resourceVersion: ""
```

```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
sudo wget -O /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-arm64
sudo chmod a+x /usr/local/bin/argocd
argocd login $(kubectl get -o jsonpath='{.spec.clusterIP}' -n argocd svc argocd-server)
argocd cluster add  default --in-cluster
```

