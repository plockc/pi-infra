## Quick Setup

```
kubectl create namespace argocd
kubectl config set-context --current --namespace=argocd
kubectl create -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: default
  namespace: argocd
  # Finalizer that ensures that project is not deleted until it is not referenced by any application
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  sourceRepos:
  - '*'
  destinations:
  - namespace: '*'
    server: '*'
  clusterResourceWhitelist:
  - group: '*'
    kind: '*'
EOF

```

See an example

```
kubectl create -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: guestbook
EOF
```

Another example

```
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: disk8s
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/plockc/disk8s.git
    targetRevision: main
    path: environments/default
    directory:
      include: disk8s.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: disk8s-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    retry:
      backoff:
        duration:      15s
        factor:        2
        maxDuration:  2m
      limit:           -1
EOF
```

