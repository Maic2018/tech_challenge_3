# ToggleMaster — Tech Challenge Fase 3 (IaC + DevSecOps + GitOps)

Plataforma de feature flags em 5 microsserviços (**auth**, **flag**, **targeting**,
**evaluation**, **analytics**) rodando em Kubernetes (EKS). Na Fase 3 a regra é
**"se não está no código, não existe"**: infraestrutura imutável via Terraform,
pipelines de segurança (DevSecOps) e deploy por GitOps com ArgoCD.

| Requisito do enunciado | Onde está |
|---|---|
| Terraform modular: VPC, EKS + LabRole, 3× RDS, ElastiCache, DynamoDB, SQS, 5× ECR | [`infra/`](infra/) + [`infra/modules/`](infra/modules/) |
| State remoto em S3 (versionado, criptografado) com lock via `use_lockfile` | [`infra/main.tf`](infra/main.tf) + [`scripts/bootstrap-backend.sh`](scripts/bootstrap-backend.sh) |
| 1 workflow por microsserviço, em Pull Request e push na `main` | [`.github/workflows/<serviço>.yml`](.github/workflows/) |
| Build & Unit Test → Lint → SCA + SAST (bloqueia em CRITICAL) → Docker build + Trivy image + push no ECR com tag do commit | [`.github/workflows/_service-ci.yml`](.github/workflows/_service-ci.yml) |
| Repositório GitOps só com manifestos | [`gitops/`](gitops/) |
| CI atualiza a tag da imagem no `deployment.yaml` | job 5 do pipeline + [`scripts/update-image-tag.sh`](scripts/update-image-tag.sh) |
| ArgoCD instalado via Terraform (provider helm) com sync automático dos 5 serviços | [`infra/platform/`](infra/platform/) |
| Credenciais fora de arquivos de texto | `random_password` + AWS Secrets Manager + Secrets do Kubernetes criados pelo Terraform |

## Como o fluxo funciona

```
 dev ──push/PR──▶ GitHub Actions (por microsserviço)
                  │ 1. build + testes unitários
                  │ 2. lint (golangci-lint / flake8)
                  │ 3. SCA (Trivy fs) + SAST (gosec / bandit)  ──▶ CRITICAL? FALHA
                  │ 4. docker build ─▶ Trivy image ─▶ login ECR ─▶ push :v1.0.0-<sha>
                  │ 5. commit em gitops/apps/<svc>/deployment.yaml com a nova tag
                  ▼
        gitops/ (mesmo repo, pasta separada) ◀──── ArgoCD (a cada 60s) ────▶ EKS
                                                    prune + selfHeal            │
 Terraform ──▶ infra/ (VPC, EKS, RDS, Redis, DynamoDB, SQS, ECR, Secrets Manager)
           ──▶ infra/platform/ (ArgoCD, ingress-nginx, metrics-server, namespace, Secrets)
```

- Ninguém roda `kubectl apply` da máquina local: o cluster converge para o que está em `gitops/`.
- Segredos (senha do RDS, MASTER_KEY, chave interna de API) são gerados pelo Terraform,
  guardados no state remoto (S3 com SSE) e no Secrets Manager, e entregues ao cluster como
  `Secret` pelo próprio Terraform. Os manifestos só os referenciam pelo nome.
- **AWS Academy:** nada de IAM. A `LabRole` é lida via `data "aws_iam_role"` e usada pelo
  cluster e pelos nodes. Como não dá para criar uma role OIDC para o GitHub, o pipeline usa
  access keys da sessão do lab guardadas como Secrets do repositório
  (`scripts/set-github-secrets.sh` renova a cada sessão).

## Estrutura do repositório

```
├── auth-service/ flag-service/ targeting-service/ evaluation-service/ analytics-service/
│     código + Dockerfile (multi-stage, não-root) + testes unitários (Go)
├── infra/                    # Terraform — root module da infraestrutura AWS
│   ├── main.tf               # backend S3 + provider + chamada dos módulos
│   ├── secrets.tf            # random_password + Secrets Manager
│   ├── modules/{network,eks,rds,elasticache,dynamodb,sqs,ecr}/
│   ├── platform/             # 2º root module: ArgoCD, ingress, metrics-server, Secrets K8s
│   │   └── argocd/           # ApplicationSet (5 serviços) + Application (platform)
│   └── 00-check-account.sh
├── gitops/                   # repositório GitOps (só manifestos)
│   ├── apps/<serviço>/       # deployment.yaml, service.yaml (+ hpa.yaml)
│   └── platform/             # configmap.yaml, ingress.yaml
├── .github/workflows/        # _service-ci.yml (reutilizável) + 5 chamadores + terraform-ci.yml
├── scripts/                  # bootstrap-backend, tf-init, set-github-secrets, trigger-ci,
│                             # update-image-tag, get-api-key, argocd-info, wait-argocd-sync
├── run-all.sh                # sobe tudo do zero (ordem certa)
├── destroy-all.sh            # derruba tudo (plataforma → infra → bucket opcional)
├── run-migrations.sh         # Job in-cluster: cria tabelas + registra chave interna
├── test-fluxo-completo.sh    # teste ponta a ponta via Load Balancer
└── docker-compose.yml        # ambiente local (LocalStack para SQS/DynamoDB)
```

## Pré-requisitos

- AWS CLI v2 com as credenciais da sessão do Academy (`aws sts get-caller-identity` funcionando)
- Terraform **>= 1.10** (o lock do state usa `use_lockfile`)
- kubectl
- GitHub CLI (`gh auth login`) — usado para publicar os Secrets e disparar o pipeline
- Docker só é necessário para o fallback local (`build-and-push.sh`) ou para o docker-compose

## Subindo o ambiente

```bash
gh auth login            # uma vez
bash run-all.sh          # ~30 min; AUTO_APPROVE=1 pula a confirmação do plan
```

O `run-all.sh` executa, nesta ordem:

| # | Passo | Comando equivalente |
|---|---|---|
| 1 | Identidade AWS + LabRole | `bash infra/00-check-account.sh` |
| 2 | Bucket S3 do state (versionado, SSE, sem acesso público) | `bash scripts/bootstrap-backend.sh` |
| 3 | Infraestrutura | `bash scripts/tf-init.sh infra && terraform -chdir=infra plan && terraform -chdir=infra apply` |
| 4 | kubeconfig | `aws eks update-kubeconfig --name togglemaster-cluster --region us-east-1` |
| 5 | Imagens via pipeline (publica no ECR e atualiza `gitops/`) | `bash scripts/set-github-secrets.sh && bash scripts/trigger-ci.sh main` |
| 6 | Plataforma: ArgoCD, ingress-nginx, metrics-server, namespace e Secrets | `bash scripts/tf-init.sh platform && terraform -chdir=infra/platform apply` |
| 7 | Migrations + chave interna do evaluation-service | `bash run-migrations.sh` |
| 8 | Espera o ArgoCD sincronizar e testa o fluxo | `bash scripts/wait-argocd-sync.sh && bash test-fluxo-completo.sh <URL>` |

Ao final ele imprime a URL da aplicação e a URL/senha do ArgoCD (`bash scripts/argocd-info.sh`).

> O `workflow_dispatch` usado no passo 5 exige que os workflows existam na branch `main`.
> Depois do merge, qualquer push que altere um serviço dispara o pipeline dele sozinho.
> Repositório privado? Exporte `GITOPS_REPO_TOKEN=<token de leitura>` antes do `run-all.sh`.

## O pipeline de cada microsserviço

Arquivo: [`.github/workflows/_service-ci.yml`](.github/workflows/_service-ci.yml), chamado pelos
5 workflows `<serviço>.yml` (que só rodam quando a pasta do serviço muda).

| Job | Go (auth, evaluation) | Python (flag, targeting, analytics) | Regra de bloqueio |
|---|---|---|---|
| 1. Build & Unit Test | `go build`, `go test -race` | `pip install`, `compileall`, `pytest` se houver | falha de build/teste |
| 2. Linter | golangci-lint (`.golangci.yml`) | flake8 (`.flake8`) | qualquer achado |
| 3. SCA | Trivy fs em `go.mod`/`go.sum` + segredos | Trivy fs em `requirements.txt` + segredos | **CRITICAL** |
| 3. SAST | gosec | bandit | HIGH (gosec) / MEDIUM+ (bandit) |
| 4. Container | `docker build` → Trivy image → login ECR → push `v1.0.0-<sha7>` | idem | **CRITICAL** na imagem |
| 5. GitOps | `scripts/update-image-tag.sh` + commit `[skip ci]` em `gitops/apps/<svc>/deployment.yaml` | idem | — |

Em Pull Request os jobs 1–4 rodam (sem push para o ECR); em push na `main` tudo roda e o
job 5 commita a nova tag. Um `concurrency group` serializa os commits dos 5 pipelines.
[`terraform-ci.yml`](.github/workflows/terraform-ci.yml) valida `fmt`/`validate` dos dois
root modules e roda `trivy config` (informativo) na IaC.

### Achados aceitos do scan de IaC (`trivy config`, informativo)

| Achado | Decisão |
|---|---|
| EKS com endpoint público / CIDR aberto (AVD-AWS-0040/0041) | Necessário no Academy (IP de saída muda). Restrinja com `eks_public_access_cidrs` quando possível. |
| Egress irrestrito nos security groups (AVD-AWS-0104) | Nodes precisam sair para ECR, SQS, DynamoDB e GitHub via NAT. |
| Tags do ECR mutáveis (AVD-AWS-0031) | Permite reexecutar o pipeline do mesmo commit; troque `image_tag_mutability` para `IMMUTABLE` se preferir. |
| Secrets do EKS sem KMS (AVD-AWS-0039) | Exigiria criar chave KMS; fora do escopo do laboratório. |

## GitOps e ArgoCD

- `infra/platform` instala o ArgoCD (chart `argo-cd`) e registra um **ApplicationSet** que
  gera uma Application por pasta em `gitops/apps/*` (os 5 microsserviços) mais uma Application
  para `gitops/platform` (ConfigMap + Ingress). Sync automático com `prune` e `selfHeal`,
  reconciliação a cada 60 s.
- UI: `bash scripts/argocd-info.sh` (usuário `admin`, senha inicial gerada pelo ArgoCD).
- Para promover uma versão basta o pipeline commitar a tag; para voltar, `git revert` do commit
  de GitOps. Alterações manuais no cluster são desfeitas pelo `selfHeal`.

## Roteiro sugerido para o vídeo

1. **IaC:** `terraform -chdir=infra plan` / `apply` (ou os recursos no console) e o state em
   `s3://togglemaster-tfstate-<account>/infra/terraform.tfstate`.
2. **Pipeline falhando:** em uma branch, adicione `PyYAML==5.3.1` ao
   `flag-service/requirements.txt` (CVE-2020-14343, CRITICAL) ou volte `pgx` para `v5.5.0` no
   `auth-service/go.mod` (CVE-2024-27304, CRITICAL). Abra o PR: o job **3. Security Scan** falha
   e o Docker build não roda. Remova a dependência: o pipeline passa.
3. **GitOps:** mostre o commit `ci(gitops): <svc> -> v1.0.0-<sha> [skip ci]` alterando
   `gitops/apps/<svc>/deployment.yaml`.
4. **ArgoCD:** a UI detecta o commit, sincroniza e o Deployment troca a imagem
   (`kubectl -n togglemaster get deploy -o wide`).

## Testes e operação

```bash
bash test-fluxo-completo.sh http://<lb-do-ingress>     # cria flag, regra, avalia
bash update-api-key.sh http://<lb-do-ingress> minha-app # chave extra para clientes
bash tools/hey-wrapper.sh -z 3m -c 150 -H "Authorization: Bearer $(cat api_key.txt)" \
  "http://<lb>/evaluate/evaluate?flag_name=nova_ui&user_id=user_42&country=BR"   # HPA
kubectl -n togglemaster get pods,hpa -w
```

## Destruir

```bash
bash destroy-all.sh                        # plataforma (remove os LBs) → infra
bash destroy-all.sh --delete-state-bucket  # também apaga o bucket do state
```

## Troubleshooting

| Problema | Causa / solução |
|---|---|
| `terraform init` pede bucket | use `bash scripts/tf-init.sh infra` (passa `-backend-config=bucket=...`) |
| Pipeline falha no login do ECR | credenciais do Academy expiraram: `bash scripts/set-github-secrets.sh` |
| `gh workflow run` não encontra o workflow | os arquivos precisam estar na branch `main` (faça o merge) |
| Pods em `ImagePullBackOff` | a tag em `gitops/` ainda aponta para outro account/imagem: rode o pipeline |
| ArgoCD `Unknown`/`ComparisonError` | repositório privado sem token: `GITOPS_REPO_TOKEN=...` no apply da plataforma |
| Pods sem credenciais AWS (SQS/DynamoDB) | hop limit do IMDS: já corrigido no launch template; fallback `fix-imds-hop-limit.sh` |
| `Application` com Ingress em erro | ingress-nginx ainda subindo; o ArgoCD tenta de novo (retry) |

## Desenvolvimento local

```bash
docker compose up --build   # 5 serviços + 3 Postgres + Redis + LocalStack (SQS/DynamoDB)
```
