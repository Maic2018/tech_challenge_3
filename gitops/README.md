# gitops/ — estado desejado do cluster

Esta pasta é o **repositório GitOps** do ToggleMaster (pasta separada no monorepo,
como o enunciado permite). Só contém manifestos Kubernetes; o ArgoCD a monitora e
sincroniza automaticamente para o cluster EKS. Ninguém roda `kubectl apply` daqui.

```
gitops/
├── apps/                       # 1 Application do ArgoCD por pasta (ApplicationSet)
│   ├── auth-service/           # deployment.yaml + service.yaml
│   ├── flag-service/
│   ├── targeting-service/
│   ├── evaluation-service/     # + hpa.yaml
│   └── analytics-service/      # + hpa.yaml
└── platform/                   # Application "togglemaster-platform": ConfigMap + Ingress
```

- A linha `image:` de cada `deployment.yaml` é alterada **pelo pipeline de CI**
  (`scripts/update-image-tag.sh`), com a tag do commit (`v1.0.0-<hash>`).
- Secrets **não** ficam aqui: são criados pelo Terraform (`infra/platform`) e apenas
  referenciados pelo nome nos Deployments.
- Namespace: `togglemaster` (criado pelo Terraform). ArgoCD com `prune` + `selfHeal`.
