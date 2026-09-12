# Roteiro de vídeo — ToggleMaster Fase 3 (20 min)

Terraform (IaC) + Pipelines DevSecOps (CI) + GitOps/ArgoCD (CD) — Projeto FIAP.

> Ferramentas prontas neste repo: `docs/scripts/preparar-apresentacao.sh` (FASE 0) e os pares
> `provocar-{sca,sast,lint}.sh` / `reverter-{sca,sast,lint}.sh` (cenas de falha).

---

## 0. Antes de gravar (obrigatório)

Rode a FASE 0 (cria tudo na AWS `248530551510`/us-east-1):

```bash
cd docs/scripts
AWS_PROFILE=tf bash preparar-apresentacao.sh            # passa por cada fase com Enter
# ensaio (ou para o apresentador sem AWS): 
AWS_PROFILE=tf bash preparar-apresentacao.sh --dry-run  # imprime todos os comandos
```

Ao final o script exibe um checklist (pipelines verdes, ECR, GitOps bumped, ArgoCD Healthy, pods Running).
**Só grave depois desse checklist 100% SIM.**

---

## 1. Estrutura do vídeo

| Tempo | Cena | O que aparece |
|---|---|---|
| 0:00–1:30 | Abertura | Diagrama + promessa "tudo é código" |
| 1:30–6:00 | 1. IaC (Terraform) | Árvore → código → plan → apply → Console AWS |
| 6:00–11:30 | 2. CI DevSecOps | Grafo verde → lint/security → **falha SCA → correção → verde** |
| 11:30–15:00 | 3. CD / GitOps | `update-gitops` → bump newTag → commit |
| 15:00–19:00 | 4. ArgoCD | UI 5 apps → sync automático → rollout |
| 19:00–20:00 | Encerramento | Mapa dos 3 entregáveis FIAP |

---

## 2. Cena 1 — IaC (Terraform) · 4:30

**Janela 1 (terminal).** Árvore de módulos:

```bash
tree terraform terraform/modules -d
```

Mostrar `terraform/main.tf` e `terraform/versions.tf`:
```hcl
backend "s3" {
  bucket       = "togglemaster-tfstate-248530551510"
  key          = "togglemaster/terraform.tfstate"
  region       = "us-east-1"
  encrypt      = true
  use_lockfile = true
}
```
Narração: *"O tfstate NUNCA fica local: bucket S3 com versionamento, SSE-S3 e lock via `use_lockfile`."*

**Janela 1.** Plan + apply ao vivo:

```bash
export AWS_PROFILE=tf
cd terraform && terraform plan -out=plan.out   # lista verde (~20 recursos)
terraform apply plan.out                       # (se já aplicado, rode de novo para filmar)
aws eks update-kubeconfig --name togglemaster-eks --region us-east-1
```

**Janela 2 (Console AWS).** VPC `/16`, EKS `togglemaster-eks`, RDS ×3, ElastiCache, DynamoDB `ToggleMasterAnalytics`, SQS, ECR ×5, IAM role `togglemaster-github-ci-role`.

**Vínculo com a rubrica FIAP:**

| Exigência FIAP | Onde está no código |
|---|---|
| Networking (VPC, subnets pub/priv, IGW, RT) | `main.tf` → `module "networking"` |
| Cluster EKS + Node Groups | `main.tf` → `module "eks"` |
| 3× RDS PostgreSQL | `main.tf` → `module "rds"` |
| ElastiCache Redis | `main.tf` → `module "elasticache"` |
| DynamoDB ToggleMasterAnalytics | `main.tf` → `module "dynamodb"` |
| Fila SQS | `main.tf` → `module "sqs"` |
| 5× ECR | `main.tf` → `module "ecr"` |
| Backend remoto S3 + lock | `versions.tf` |

---

## 3. Cena 2 — Pipeline DevSecOps · 5:30

**Janela GitHub Actions:** abrir 1 pipeline (ex.: `auth CI`) → **grafo de 5 jobs**.

**Mostrar a chamada** `.github/workflows/auth-ci.yml:29-38`:
```yaml
jobs:
  ci:
    uses: ./.github/workflows/_ci-reusable.yml
    with:
      service-name: auth-service
      working-directory: auth-service
      language: go
      go-version-file: auth-service/go.mod
      ecr-repository: togglemaster-auth
```
Narração: *"1 workflow por serviço; a lógica vive no reutilizável `_ci-reusable.yml` com 5 jobs encadeados: build-test → lint → security-scan → docker-build-scan-push → update-gitops. PR roda 1–3; push na main roda os 5."*

**Abrir jobs verdes:**
- `Lint` — mostra `golangci-lint run` (`_ci-reusable.yml:157-158`) e `flake8+pylint` (`:179-181`).
- `Security Scan` — 4 passos: `Trivy FS` visibilidade → `Trivy FS GATE` → `gosec` → `bandit`; todos `Total: 0`.

### ✂️ Prova de falha — SCA (2 min)

```bash
bash docs/scripts/provocar-sca.sh        # SCA: x/crypto v0.20.0 → CVE-2026-56854 CRITICAL
```
Filmar: run **VERMELHO** parado em `Security Scan → Trivy FS - GATE CRITICAL`, log citando `CVE-2026-56854`.
Depois:
```bash
bash docs/scripts/reverter-sca.sh        # mostra a CORREÇÃO (revert) e o run verde
```
Narração: *"CRITICAL • o pipeline para aqui: não chega no Docker nem no deploy. A correção da dependência volta o verde."*

> Opcionais (se sobrar tempo), mesma mecânica:
> ```bash
> bash docs/scripts/provocar-sast.sh  && bash docs/scripts/reverter-sast.sh   # gosec 4× G704 SSRF HIGH
> bash docs/scripts/provocar-lint.sh  && bash docs/scripts/reverter-lint.sh   # golangci 'unused'
> ```

---

## 4. Cena 3 — CD / GitOps · 3:30

No log do 5º job (`Update GitOps - nova tag`), mostrar o que o CI fez (`_ci-reusable.yml:337-353`):
```bash
FILE="gitops/apps/auth-service/kustomization.yaml"
yq -i '.images[0].newTag = strenv(NEW_TAG)' "$FILE"
git commit -m "ci(auth-service): bump image to ${NEW_TAG}"
git push
```
**Janela terminal** (prova no repositório):
```bash
git log --oneline -3
git show HEAD --stat | head                       # só 1 arquivo mudou
cat gitops/apps/auth-service/kustomization.yaml | grep newTag   # v1.0.0-<sha7>
```
Narração: *"Nenhum kubectl no pipeline: a CI só altera uma tag em YAML. O repositório GitOps é a fonte de verdade."*

---

## 5. Cena 4 — ArgoCD · 4:00

**Janela 1 (terminal):**
```bash
# senha inicial do admin do ArgoCD:
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
kubectl port-forward svc/argocd-server -n argocd 8080:443   # browser: https://localhost:8080
```

**Janela 2 (UI ArgoCD):** login `admin` + senha. Mostrar as **5 Applications Healthy** e o
`syncPolicy: automated (prune + selfHeal)` de `gitops/argocd/applications/auth-service.yaml:26-33`.

**★ Clímax — sync automático:** com a UI e o terminal do ArgoCD visíveis:

```bash
bash docs/scripts/provocar-lint.sh   # dispara novo commit (ou use reverter-sca.sh já pendurado...)
```
> Na prática, qualquer push gera bump no GitOps → ArgoCD detecta **OutOfSync** → synchronized.
Fechar com:
```bash
kubectl rollout status deployment/auth-service -n feature-flags --timeout=180s
kubectl get pods -n feature-flags
```
Narração: *"O GitOps mudou um YAML; o ArgoCD convergiu o cluster sozinho. Estado real = estado desejado."*

---

## 6. Cena 5 — Encerramento (1 min)

Mapa de entrega FIAP — fechar o vídeo com esta tela:

| Entregável FIAP | Onde provar |
|---|---|
| 1. Terraform com backend remoto | Cena 1 (`versions.tf`, bucket, plan/apply) |
| 2. CI + DevSecOps (SAST/SCA com bloqueio CRITICAL) | Cena 2 (`_ci-reusable.yml`, run vermelho→verde) |
| 3. CD/GitOps (tag no repo + ArgoCD sync automático) | Cenas 3–4 (kustomization bumped, UI ArgoCD) |

---

## 7. Dicas de gravação & resolução de problemas

- **2 janelas lado a lado:** terminal + navegador (OBS/QuickTime). Faça take por cena (Ctrl-C no terminal pausa).
- **`gh` ausente?** `provocar-*.sh` ainda funciona (mostra só a URL do run). Instale com `winget install --id GitHub.cli`.
- **Push usa SSH** (`git@github.com:...`) — o HTTPS do WSL não tem credencial; os scripts já usam SSH.
- **Aviso "Node 20 deprecated"** no log: informativo, ignorar.
- **Erro "Could not load credentials from any providers":** secret `AWS_ROLE_ARN` não criado → refazer passo 8 da FASE 0.
- **ArgoCD não achou o repo:** se o repositório for **privado**, adicione o repo no ArgoCD com token:
  `argocd repo add https://github.com/maiconjfa/techchallenge2-projetofiap --username <user> --password <PAT>`.
- **Runs com `concurrency: group: ci-<serviço>`**: provocações em sequência, nunca em paralelo (os `reverter` dependem do HEAD).
- Tremo em gravar **falha real**? Cruise: prepare o `provocar-sca.sh` já editado numa quarta janela; a correção (`reverter`) restaura em 1 comando.