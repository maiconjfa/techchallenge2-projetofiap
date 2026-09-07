# ToggleMaster — Tech Challenge Fase 3

Plataforma de feature flags com 5 microsserviços, evoluída da Fase 2 (criação
manual na AWS) para **IaC com Terraform**, **CI com DevSecOps** no GitHub
Actions e **CD GitOps** com **ArgoCD + Kustomize**.

---

## Arquitetura

```
                          GitHub Actions (CI/DevSecOps)
   PR/Push main ──► build-test ─► lint ─► SAST/SCA (bloqueia CRITICAL)
                                        └► Docker build ─► Trivy image scan
                                              └► Push ECR (tag v1.0.0-<sha>)
                                                    └► commit da tag no GitOps
                                                            │
   terraform/ ─── provisiona AWS ──► EKS ◄── ArgoCD (sync automático) ─────┘
       │                              │
       ├─ VPC (pub/priv, IGW, RT)     ├─ gitops/apps/* (5 Deployments+Services)
       ├─ EKS + Node Groups           └─ gitops/base (ns, config, ingress...)
       ├─ 3× RDS PostgreSQL
       ├─ ElastiCache Redis           evaluation-service ──SQS eventos──┐
       ├─ DynamoDB (ToggleMasterAnalytics) ◄── analytics-service ◄────────┘
       ├─ SQS (+DLQ)                        (KEDA escala pela fila)
       ├─ 5× Repositórios ECR
       └─ OIDC GitHub Actions (CI sem chaves estáticas)
```

**Fluxo de requisição:** cliente → Ingress nginx → `evaluation-service`
(cache Redis; fallback flag/targeting) → evento assíncrono via SQS →
`analytics-service` → DynamoDB.

| Microsserviço | Linguagem | Porta | Banco/Dependência |
|---|---|---|---|
| auth-service | Go | 8001 | RDS `auth_db` |
| flag-service | Python/Flask | 8002 | RDS `flag_db` |
| targeting-service | Python/Flask | 8003 | RDS `targeting_db` |
| evaluation-service | Go | 8004 | Redis + SQS |
| analytics-service | Python worker | 8005 | SQS + DynamoDB |

## Estrutura do repositório

```
├── terraform/
│   ├── versions.tf            # backend S3 remoto + use_lockfile (TF >= 1.10)
│   ├── main.tf / variables.tf / outputs.tf / terraform.tfvars.example
│   ├── scripts/bootstrap-state.sh        # cria bucket de estado (1x)
│   ├── scripts/generate-k8s-secrets.sh   # Secret K8s a partir dos outputs
│   ├── argocd-install/          # camada 2: instalação do ArgoCD (estado próprio)
│   └── modules/
│       ├── networking/ eks/ rds/ elasticache/ dynamodb/ sqs/ ecr/
│       ├── github_oidc/         # role IAM p/ GitHub Actions via OIDC
│       └── argocd/              # instalação via Kustomize (kbst/kustomization)
├── .github/workflows/
│   ├── _ci-reusable.yml         # pipeline DevSecOps reutilizável
│   └── {auth,flag,targeting,evaluation,analytics}-ci.yml
├── gitops/                      # fonte única de verdade do cluster (GitOps)
│   ├── base/                    # namespace, configmap, secret*, ingress, hpa, keda, SAs
│   ├── apps/<svc>/              # deployment + service + kustomization (tag gerida pelo CI)
│   └── argocd/applications/     # 5 Applications (automated + prune + selfHeal)
└── <diretórios dos 5 microsserviços>
```

\* o `gitops/base/secrets.yaml` é **gerado** a partir dos outputs do Terraform
e não é versionado (ver `.gitignore`). Exemplo em `gitops/base/secrets.example.yaml`.

---

## Runbook de execução

### Pré-requisitos

- Terraform >= 1.10 (`use_lockfile`)
- AWS CLI v2 configurada para a conta do lab:
  ```bash
  aws configure --profile tf      # ou exporte AWS_ACCESS_KEY_ID/SECRET/TOKEN
  export AWS_PROFILE=tf
  aws sts get-caller-identity     # conta esperada: 248530551510
  ```
- kubectl, jq, docker (para builds locais opcionais)

### 1. Estado remoto (uma única vez)

```bash
cd terraform/scripts && ./bootstrap-state.sh
```

Cria `s3://togglemaster-tfstate-248530551510` com versionamento + SSE.
O lock é nativo do S3 (`use_lockfile = true`) — sem tabela DynamoDB.

### 2. Provisionar a infraestrutura (camada 1)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # ajuste se necessário
terraform init
terraform apply
```

Cria: VPC + subnets públicas/privadas + IGW + route tables · EKS + node group
(t3.medium, subnets públicas) · 3× RDS PostgreSQL · ElastiCache Redis ·
DynamoDB `ToggleMasterAnalytics` · SQS + DLQ · 5 repos ECR · role OIDC do CI.

> **AWS Academy/LabRole:** informe em `terraform.tfvars` os ARNs
> `existing_cluster_role_arn` / `existing_node_role_arn` — nenhuma role nova
> será criada.

Ao final, configure o acesso ao cluster:

```bash
aws eks update-kubeconfig --name togglemaster-eks --region us-east-1
kubectl get nodes
```

### 3. Instalar o ArgoCD (camada 2)

```bash
cd terraform/argocd-install
terraform init
terraform apply
```

Instalação feita com **Kustomize puro** (manifests oficiais vendados em
`terraform/modules/argocd/manifests`, provider `kbst/kustomization`).

### 4. Preparar o namespace da aplicação

```bash
cd terraform && ./scripts/generate-k8s-secrets.sh   # gera gitops/base/secrets.yaml
cd ..
kubectl apply -k gitops/base
```

Opcionais (necessários para Ingress e autoscaling por fila):

```bash
# ingress-nginx
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/aws/deploy.yaml

# KEDA
kubectl apply -f https://github.com/kedacore/keda/releases/download/v2.15.1/keda-2.15.1.yaml -n keda --create-namespace || \
kubectl apply -f https://github.com/kedacore/keda/releases/download/v2.15.1/keda-2.15.1.yaml
```

### 5. Configurar o CI (GitHub)

No repositório GitHub (**Settings → Secrets and variables → Actions**):

| Secret | Valor |
|---|---|
| `AWS_ROLE_ARN` | saída `terraform output github_ci_role_arn` |

A autenticação usa **OIDC federation** (sem access keys estáticas). A role já
permite push apenas nos 5 repositórios `togglemaster-*`.

### 6. Fluxo CI → GitOps → ArgoCD

```bash
git checkout -b feature/exemplo     # PR: roda build/lint/SAST/SCA (sem deploy)
git push origin feature/exemplo     # abre PR no GitHub...
# ...merge na main dispara o pipeline completo:
git push origin main                # build → lint → security → docker → ECR
                                    # └► job update-gitops faz commit da nova tag
```

O job final altera `images.newTag` em `gitops/apps/<svc>/kustomization.yaml`
(ex.: `v1.0.0-a1b2c3d`). O ArgoCD detecta o commit e sincroniza o cluster.

Para sincronizar manualmente as Applications na primeira vez:

```bash
kubectl apply -k gitops/apps/auth-service        # opcional: deploy imediato
kubectl apply -f gitops/argocd/applications      # registra as 5 Applications
watch kubectl get applications -n argocd         # todos devem ficar Synced/Healthy
```

### 7. Interface do ArgoCD (evidência dos 5 microsserviços)

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# senha inicial:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

Acesse `https://localhost:8080` (usuário `admin`). Em **Applications** devem
aparecer os 5 cards (`auth-service`, `flag-service`, `targeting-service`,
`evaluation-service`, `analytics-service`) como *Synced/Healthy* — screenshot
desta tela compõe a evidência do desafio.

### 8. Destruir o ambiente (evitar custos)

```bash
kubectl delete -k gitops/base --ignore-not-found
kubectl delete applications -n argocd --all
cd terraform/argocd-install && terraform destroy && cd ..
terraform destroy
```

---

## Pipeline CI — estágios e regra de bloqueio

| Job | Ferramentas | Bloqueio |
|---|---|---|
| Build & Unit Test | `go build/test` · `pytest`/`compileall` | falha de build/teste |
| Linter | golangci-lint · flake8 (E9,F63,F7,F82) + pylint errors-only | erro fatal |
| Security Scan (SCA) | Trivy fs (vuln/secret/misconfig) | **CRITICAL** |
| Security Scan (SAST) | gosec (Go) · bandit `-lll` (Python) | HIGH/CRITICAL |
| Docker & Container Scan | Trivy image | **CRITICAL** |
| Push ECR | OIDC → tag `v1.0.0-<sha7>` + latest | erro de push |
| Update GitOps | yq no `kustomization.yaml` + commit | erro de commit |

Pull Requests executam os 3 primeiros estágios; push na `main` executa tudo,
incluindo deploy via GitOps.

## Custos estimados (pro-rata diário)

| Recurso | ~US$/dia |
|---|---|
| EKS control plane | 2,40 |
| 2× t3.medium | 1,90 |
| 3× db.t4g.micro (20GB) | 1,50 |
| cache.t4g.micro | 0,40 |
| SQS/DynamoDB/ECR | ~0 (free tier/baixo uso) |
| **Total** | **~6,20/dia** |

Use o runbook do passo 8 ao encerrar os testes.

## Segurança — notas

- Senhas RDS geradas por `random_password`; expostas apenas nos outputs
  sensíveis e no Secret K8s gerado localmente.
- `terraform.tfstate` nunca fica local (backend S3 versionado + lockfile).
- Sem credenciais estáticas no CI (OIDC); trust policy restrita ao repo/main/PR.
- Subnets privadas sem rota de internet hospedam RDS e Redis (acesso somente
  pelo SG do cluster).
