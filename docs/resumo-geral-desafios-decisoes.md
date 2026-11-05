# ToggleMaster — Resumo Geral: O que foi criado, implantado, desafios e decisões

> Conta AWS: **248530551510** · Região: **us-east-1** · Repo: `maiconjfa/techchallenge2-projetofiap` · Status em 14/set/2026

Este documento consolida **todo o projeto** — do ponto de partida (Fase 2 manual) até a Fase 3 (IaC + DevSecOps + GitOps) — com o que foi **criado e de fato implantado**, os **desafios enfrentados** e as **decisões tomadas** (com o motivo de cada uma).

---

## 1. Visão geral

| Fase | O que era | Como ficou |
|---|---|---|
| **Fase 2** | 5 microsserviços de feature flags criados e provisionados **manualmente** na AWS | Entregue |
| **Fase 3** | Evolução para **Infraestrutura como Código (Terraform)**, **CI/CD DevSecOps (GitHub Actions)** e **GitOps (ArgoCD + Kustomize)** | **Completa — tudo implantado e funcionando** |

**Aplicação:** plataforma de feature flags com 5 microsserviços:

| Microsserviço | Linguagem | Porta | Banco / dependência |
|---|---|---|---|
| auth-service | Go | 8001 | RDS PostgreSQL `auth_db` |
| flag-service | Python/Flask | 8002 | RDS PostgreSQL `flag_db` |
| targeting-service | Python/Flask | 8003 | RDS PostgreSQL `targeting_db` |
| evaluation-service | Go | 8004 | Redis + SQS |
| analytics-service | Python (worker) | 8005 | SQS + DynamoDB |

**Fluxo:** cliente → (Ingress) → `evaluation-service` (cache Redis) → resposta; evento assíncrono via **SQS** → `analytics-service` → **DynamoDB**. O `analytics-service` escala por fila (KEDA) e o `evaluation-service` por CPU (HPA).

---

## 2. O que foi criado e implantado

### 2.1 Infraestrutura AWS — Terraform (Camada 1)

Módulos em `terraform/modules/`, com backend S3 remoto (`togglemaster-tfstate-248530551510`, versionado + criptografado) e lock nativo do S3.

| Módulo | Recursos criados | Status no ambiente |
|---|---|---|
| `networking` | VPC `togglemaster-vpc` (10.0.0.0/16), 2 subnets públicas (nodes EKS), 2 privadas (RDS/Redis), IGW, rotas | Implantado |
| `eks` | Cluster `togglemaster-eks` (Kubernetes v1.36), node group `togglemaster-workers` (2× t3.medium on-demand, AL2023, disco 20 GB) | Implantado, ACTIVE |
| `rds` | 3× RDS PostgreSQL 16.15 `db.t4g.micro`, 20 GB, single-AZ (`auth`, `flag`, `targeting`) | Implantado, available |
| `elasticache` | Redis `cache.t4g.micro` (`togglemaster-redis`) | Implantado, available |
| `dynamodb` | Tabela `ToggleMasterAnalytics` (PAY_PER_REQUEST, hash `event_id`) | Implantado |
| `sqs` | Fila `tooglemaster-evaluation-events-queue` + **DLQ** (redrive após 5 tentativas, retenção 14 dias) | Implantado |
| `ecr` | 5 repositórios (`togglemaster-{auth,flag,targeting,evaluation,analytics}`), **scan on push**, lifecycle (descarta untagged 7d e mantém 10 imagens) | Implantado |
| `github_oidc` | Provider OIDC + role `togglemaster-github-ci-role` (trust: repo + main/PR/environments), policies de ECR | Implantado |

### 2.2 ArgoCD (Camada 2) — `terraform/argocd-install/`

- Estado próprio (backend separado), instalado **via Kustomize puro** com provider `kbst/kustomization` (server-side apply com detecção de drift; precedência por grupos: namespaces/CRDs → cluster-scoped → namespaced).
- **Implantado**: 5 Applications (`auth`, `flag`, `targeting`, `evaluation`, `analytics`) com `automated` (prune + selfHeal), retry com backoff, namespace `feature-flags`.

### 2.3 GitOps — Kustomize (`gitops/`)

- `gitops/base/`: namespace, configmap `app-config`, **secret gerado** `app-secrets` (não versionado), ingress (5 rotas), HPA, KEDA, service accounts.
- `gitops/apps/<svc>/`: deployment + service (ClusterIP) + kustomization com tag controlada pelo CI (`images.newTag`).
- Deployments: auth/flag/targeting ×2 réplicas, evaluation ×2, analytics ×1, com probes de liveness/readiness e recursos (requests 128m/128Mi, limits 256m/256Mi).

### 2.4 CI/CD — GitHub Actions (`.github/workflows/`)

Pipeline **reutilizável** `_ci-reusable.yml` (workflow_call) + 5 workflows de serviço. Estágios encadeados com regras de bloqueio:

| Estágio | Ferramenta | Regra de bloqueio |
|---|---|---|
| Build & Test | `go build`/`go test` · `pytest`/`compileall` | erro de build/teste |
| Lint | golangci-lint v2.13.2 · flake8 (E9,F63,F7,F82) + pylint `--errors-only` | erro fatal |
| SCA | Trivy FS (vuln/secret/misconfig) | **CRITICAL/HIGH** |
| SAST | gosec (Go) · bandit `-lll` (Python) | **HIGH** |
| Docker & Scan | Docker build + Trivy image | **CRITICAL** (na imagem) |
| Push ECR | OIDC (`configure-aws-credentials`) + `amazon-ecr-login` | erro de push |
| Update GitOps | yq no `kustomization.yaml` + commit | erro de commit |

- **PR**: executa estágios 1–3. **Push na `main`**: executa tudo (inclui deploy via GitOps).
- Tags `v1.0.0-<sha7>` + `latest`; imagens **MUTABLE** (permite retry de pipeline).

### 2.5 Segurança aplicada

- **OIDC federation** — nenhuma access key estática no CI; trust policy restrita ao repositório/`main`/PR.
- Secret `AWS_ROLE_ARN` é o único segredo repo-level.
- Senhas RDS via `random_password`; DBs em subnets privadas acessíveis **somente** pelo SG do node.
- Secrets K8s **gerados localmente** do output do Terraform (nunca versionados).
- ECR scan no push + gates SAST/SCA/container no pipeline.
- Backend remoto com SSE + lock.

### 2.6 Implantação real confirmada (14/set/2026)

```
EKS togglemaster-eks ........ ACTIVE (v1.36)  | nodes: 2× t3.medium (AZ a/b)
RDS .............................. 3× available (postgres 16.15)
Redis togglemaster-redis ......... available (cache.t4g.micro)
DynamoDB ToggleMasterAnalytics .. PAY_PER_REQUEST
SQS ................. tooglemaster-evaluation-events-queue (+ DLQ)
ECR .............................. 5 repos
ArgoCD ................... 5 Applications Synced/Healthy (42 APIs objetos gerenciados)
Pods feature-flags ....... 10 Running (auth×2, flag×2, targeting×2, evaluation×2, analytics×1)
```

**Evidências do ciclo CD:** o histórico git mostra a sequência real `demo(gitops) → 5× ci(<svc>): bump image → ArgoCD sincroniza` — o pipeline atualizou a tag e o ArgoCD convergiu o cluster sozinho (3 rodadas completas registradas no `git log`).

---

## 3. Custos

Estimativa detalhada, preços confirmados via AWS Pricing API e passo a passo para gerar o link compartilhável do AWS Pricing Calculator estão em **`docs/resumo-status-custos.md`**.

| Cenário | US$/mês | US$/dia |
|---|---|---|
| Sem exposição externa | ~193 | ~6,35 |
| Com NLB/Ingress | ~213 | ~7,01 |

---

## 4. Desafios encontrados

### 4.1 Infraestrutura / AWS Academy

1. **AWS Academy não permite criar IAM** — o Terraform `aws_iam_role` falhava no ambiente do laboratório.
2. **Custo de NAT** — 2 NAT Gateways (~US$ 65/mês) inviabilizavam o lab; subnets privadas sem rota de internet não conseguem egresso.
3. **Backend remoto sem tabela de lock** — o padrão (bucket S3 + tabela DynamoDB `terraform`-lock) adicionava complexidade.
4. **Ordem de criação EKS → ArgoCD** — ArgoCD exige cluster pronto e kubeconfig; um único módulo falharia por dependência cíclica.
5. **Secrets não podem ser versionados junto com o GitOps** — o Git é a fonte da verdade, mas um Secret com senha não pode ficar no repo.

### 4.2 CI/CD

6. **5 pipelines concorrentes escrevendo no mesmo repositório GitOps** — push simultâneo gerava conflitos de commit/perda de atualização de tag.
7. **Retry de pipeline com tag imutável** — re-executar o pipeline que reenvia o mesmo SHA falhava no ECR com tag `IMMUTABLE`.
8. **gosec não tem severidade CRITICAL** — o gate de bloqueio precisava ser mapeado corretamente.
9. **golangci-lint v2 mudou o caminho do módulo** — `go install github.com/golangci/golangci-lint/cmd/golangci-lint` quebrava na v2.
10. **Serviços Python sem testes unitários** — `pytest` falhava (`no tests ran`) e o build do `pip install` demorava.
11. **Scan Trivy × regra de bloqueio** — era preciso separar "relatório para visibilidade" (não bloqueia) de "gate" (bloqueia CRITICAL/HIGH).
12. **Trivy image scan antes do push** — precisava de login ECR e de uma tag estável local (SHA) para validar a imagem before deploying.

### 4.3 Kubernetes / runtime

13. **HPA sem métricas** — sem `metrics-server` instalado, o HPA não escala.
14. **Ingress sem controller** — o Ingress resource existe, mas o controller nginx não estava instalado no cluster (acesso era por port-forward).
15. **Nome da fila com o typo histórico** — a fila foi criada como `tooglemaster-...` (formatura "toggle") e o KEDA/ingress a referenciam pelo ARN.

---

## 5. Decisões tomadas (e o motivo)

| # | Decisão | Motivo / trade-off |
|---|---|---|
| 1 | **Reusar LabRole existente** (`existing_cluster_role_arn` / `existing_node_role_arn`) | AWS Academy não cria IAM; variáveis permitem "modo próprio" (cria role) ou "modo Academy" (reusa) sem mudar o código |
| 2 | **Sem NAT; nodes em subnets públicas** | Elimina ~US$ 65/mês de NAT; explicado no código (`# custo zero de egress lab`). Trade-off: nodes em frente à internet, mitigado por SG |
| 3 | **`use_lockfile = true` no S3 (Terraform ≥ 1.10)** | Lock nativo do bucket — dispensa a tabela DynamoDB de lock |
| 4 | **ArgoCD em camada/estado separado** | Resolve a dependência cluster→ArgoCD; permite `destroy` independente |
| 5 | **Manifests do ArgoCD via Kustomize puro + `kbst/kustomization`** | Sem Helm; vendor dos manifests oficiais; drift detectado pelo state |
| 6 | **ECR com tags MUTABLE** | Retry de pipelines que reenviam o mesmo commihash; mitigado com lifecycle policy |
| 7 | **concurrency `gitops-update` (serializa) + `git pull --rebase`** | 5 pipelines empurram no mesmo arquivo GitOps sem conflito; o rebase absorve os bumps concorrentes |
| 8 | **`workflow_call` reutilizável** | DRY — a lógica DevSecOps fica num único arquivo; cada serviço só passa inputs |
| 9 | **Gate de SCA em CRITICAL/HIGH no FS e CRITICAL na imagem** | Código/dependências mais rígidos que a imagem base (evita falso gatilho em base image) |
| 10 | **SAST: gosec HIGH / bandit `-lll`** | SAST tem menos falsos positivos que SCA; gosec não tem CRITICAL (HIGH = topo) |
| 11 | **Python: flake8 apenas erros fatais + pylint `--errors-only`** | Estilo não bloqueia; só erro real, evitando poluição de ruído no pipeline |
| 12 | **Python sem testes → `compileall` como fallback** | Pipeline nunca fica bloqueado por `no tests ran`; valida sintaxe |
| 13 | **Tags `v1.0.0-<sha7>` + `latest`; CI edita `images.newTag` via yq** | Versão determinística + rastreável ao commit; o "deploy" é só um commit no GitOps |
| 14 | **PR executa só build/test/lint/security; main executa tudo** | PR dá feedback rápido e seguro sem deploy; main dispara CD |
| 15 | **Secrets K8s gerados de scripts (não versionados)** | GitOps sem vazar senhas; `secrets.example.yaml` documenta o formato. Evolução futura: Sealed/External Secrets |
| 16 | **Tabela DynamoDB `PAY_PER_REQUEST`** | Custo zero em tráfego baixo de laboratório |
| 17 | **HPA (CPU) + KEDA (fila)** | duo de autoscaling de aplicação; manifest declarativo no GitOps |
| 18 | **RDS single-AZ, backup 1 dia, `skip_final_snapshot=true`** | PoC: minimiza custo e facilita destroy; HA ficou como melhoria p/ produção |
| 19 | **Endpoint público do cluster (0.0.0.0/0) no lab** | `kubectl` pela internet sem bastion/VPN; trade-off de segurança aceito no lab |
| 20 | **Mantém o typo `tooglemaster-` na fila** | O ARN está em uso nas referências (ingress/KEDA); evita quebrar contratos existentes |

---

## 6. Lições aprendidas e boas práticas (materializadas no projeto)

- **IaC por camadas com backends separados** resolve dependências de bootstrap (rede → cluster → GitOps).
- **GitOps puro exige resolver segredos** — o ponto de tensão entre "tudo é código" e "credenciais não versionadas".
- **CI como "atuador" do GitOps**: o pipeline não faz `kubectl`; ele só atualiza a tag e o ArgoCD converge. Menos privilégio, mais auditabilidade.
- **Regras de bloqueio calibradas por severidade e por estágio** (SCA mais rígido no FS, container só CRITICAL) evitam pipelines "vermelhos por causa de base image".
- **Concorrência em repositório GitOps** precisa de estratégia (serialização + rebase), senão a CD quebra no commit, não no push da imagem.
- **Custo é decisão de arquitetura**: a ausência de NAT foi deliberada e comentada no código.

---

## 7. O que está pronto para a entrega (checklist final)

- [x] 5 microsserviços rodando no EKS (10 pods, Healthy)
- [x] ArgoCD com 5 Applications Synced/Healthy (CI/CD GitOps funcional)
- [x] Pipelines DevSecOps verdes (build, lint, SAST, SCA, container scan, push ECR, GitOps bump)
- [x] Estimativa de custos (documento + passo a passo do AWS Calculator)
- [x] Roteiros de apresentação/vídeo + scripts de cena (`provocar-*`/`reverter-*`)
- [ ] Captura das evidências (screenshots da UI ArgoCD e das pipelines) — item de execução, não instalação

---

## Referências

- `docs/resumo-status-custos.md` — status, custos e arquitetura (link do Calculator)
- `docs/roteiro-detalhado.md` — playbook da banca
- `docs/gitops-argocd-demo.md` — cena GitOps/ArgoCD
- `docs/apresentacao-video.md` — roteiro de vídeo
- `README.md` — runbook completo