# Roteiro de apresentação — ToggleMaster Fase 3 (Playbook)

> **Escopo deste roteiro:** a infraestrutura (Terraform) e a instalação do ArgoCD **já foram
> executadas**. Aqui você tem um **playbook enxuto** das duas etapas que faltam para a
> apresentação:
>
> 1. **DevSecOps** — os pipelines de CI que bloqueiam código com problema antes do deploy;
> 2. **GitOps com ArgoCD** — como o CI "entrega" escrevendo só uma tag e o ArgoCD convergir o
>    cluster sozinho.
>
> Para cada passo: uma **explicação simples**, o **comando exato** e **o que vai aparecer**.
> Se quiser regravar do zero (Terraform + ArgoCD inclusive), siga o **Apêndice B**.

---

## Índice

1. Ponto de partida (o que já está de pé)
2. Etapa 1 — DevSecOps: os pipelines que bloqueiam
3. Etapa 2 — GitOps + ArgoCD: o cluster converge sozinho
4. Encerramento
5. Apêndice A — Cartões de defesa da banca
6. Apêndice B — Do zero (Terraform + ArgoCD + FASE 0)
7. Apêndice C — Troubleshooting

---

## 1. Ponto de partida (o que já está de pé)

Antes de começar, confirme que o ambiente está no estado esperado. Abra um terminal na raiz do
repositório e rode a pré-checagem:

```bash
git status --porcelain          # deve estar vazio (árvore limpa)
git pull --rebase origin main   # sincroniza com o bot do CI (que comita bumps de tag no GitOps)

kubectl get applications -n argocd
kubectl get pods -n feature-flags
```

O que `kubectl get applications -n argocd` deve mostrar:

```
NAME                 SYNC      HEALTH
analytics-service    Synced    Healthy
auth-service         Synced    Healthy
evaluation-service   Synced    Healthy
flag-service         Synced    Healthy
targeting-service    Synced    Healthy
```

O que `kubectl get pods -n feature-flags` deve mostrar: os 5 serviços com **todos os pods
`Running`** e copia pronta.

Resumo do que já existe (não é preciso rodar nada disso hoje):

| Recurso | O que é | Onde nasceu |
|---|---|---|
| VPC + subnets + IGW | rede | `terraform` (módulo `networking`) |
| Cluster EKS `togglemaster-eks` | Kubernetes | `terraform` (módulo `eks`) |
| 3 RDS PostgreSQL, Redis, DynamoDB, SQS+DLQ | dados e fila | `terraform` |
| 5 repositórios ECR | imagens | `terraform` (módulo `ecr`) |
| Role `togglemaster-github-ci-role` | acesso do CI via OIDC | `terraform` (módulo `github_oidc`) |
| ArgoCD no namespace `argocd` | agente de GitOps | `terraform/argocd-install` (2ª camada) |
| 5 Applications + segredos + KEDA | contratos e escala | `kubectl apply -k gitops/base` + `gitops/argocd/applications/` |

> **Regra de ouro da apresentação:** os scripts de demonstração exigem **árvore limpa** e
> **main sincronizada** (o `git pull` acima resolve). Se um script reclamar, é isso que ele quer.

---

## 2. Etapa 1 — DevSecOps: os pipelines que bloqueiam

### 2.1 Entendendo em 1 minuto

O CI de cada serviço roda **5 estágios encadeados**. Em *Pull Request* rodam os 3 primeiros; em
*push na main* rodam os 5. **Qualquer falha interrompe o pipeline** — nada de imagem nem deploy
com problema.

| Estágio | Ferramenta | Portão (o que bloqueia) |
|---|---|---|
| 1. Build & Test | `go build`/`go test` (ou `pytest`/`compileall`) | não compila / teste falhou |
| 2. Lint | `golangci-lint` (Go) · `flake8 + pylint` (Python) | erro fatal, código morto |
| 3. Security Scan | **SCA** `Trivy FS` + **SAST** `gosec` (Go) / `bandit` (Python) | dependência **CRITICAL/HIGH** · código **HIGH** |
| 4. Docker Build & Push | `docker build` + **Trivy Image** + push no **ECR** | imagem com vulnerabilidade **CRITICAL** |
| 5. Update GitOps | `yq` + commit da tag nova | só roda em push na main |

Duas siglas que a banca adora:

- **SCA** (Software Composition Analysis) — olha as **dependências** (`go.mod`,
  `requirements.txt`) contra bancos de CVE.
- **SAST** (Static Application Security Testing) — varre o **código-fonte** em busca de padrões
  vulneráveis (ex.: SSRF).

O acesso à AWS é por **OIDC**: o runner do GitHub emite um token, a AWS valida e entrega
credenciais **temporárias** da role `togglemaster-github-ci-role` — **não há chave estática no
repositório**.

### 2.2 A arquitetura: 1 workflow por serviço + 1 reutilizável

Cada serviço tem um *caller* curto que delega a lógica a um workflow **reutilizável**
(`_ci-reusable.yml`) — a pipeline é definida **uma única vez** e reaproveitada 5×.

`auth-service` / `.github/workflows/auth-ci.yml` (os outros 4 são idênticos, só mudam caminho e
repositório ECR):

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
    secrets:
      AWS_ROLE_ARN: ${{ secrets.AWS_ROLE_ARN }}
```

Dois detalhes que **já quebraram o CI** e viraram resposta de banca:

1. **Filtro de `paths`**: o pipeline só dispara quando muda código **daquele serviço**
   (`auth-service/**`) ou os próprios workflows. Mudou só `docs/**`? Nenhum pipeline roda — é o
   comportamento esperado.
2. **Secret só entra se for declarado e repassado**: o caller repassa `AWS_ROLE_ARN` e o
   reutilizável o declara em `on: workflow_call: secrets:`. Sem isso, o valor chega **vazio** (e
   o job de push falha) ou o workflow nem inicia (`startup_failure`).

### 2.3 Comandos para a demonstração

> **Pré-requisito:** tudo verde (seção 1) e terminal na raiz do repo, branch `main`.

**Cena principal — SCA bloqueando (vermelho → verde, tudo manual):**

> O bloqueio é real: o portão SCA é `GATE CRITICAL/HIGH` e `golang.org/x/crypto v0.20.0` carrega o
> **CVE-2026-56854 (HIGH)** — o `auth-service` é o único dos 5 sem HIGHs na versão saudável, então
> o downgrade dele é o que pára o pipeline.

**Passo 0 — preparar** (sincroniza com o CI, que pode ter commitado bump no GitOps):

```bash
git pull --rebase origin main
```

**Passo 1 — commit manual do downgrade (o pipeline fica VERMELHO):**

```bash
# Regressa golang.org/x/crypto para v0.20.0 (vulnerável) e regenera o go.sum:
docker run --rm -v "$PWD":/src -w /src/auth-service golang:1.26-alpine \
  sh -c "go mod edit -require=golang.org/x/crypto@v0.20.0 && go mod tidy"

git diff --stat                      # confere: só go.mod e go.sum mudaram
git add auth-service/go.mod auth-service/go.sum
git commit -m "demo(sca): golang.org/x/crypto v0.20.0 (CVE-2026-56854 HIGH)"
git push origin main                 # dispara o pipeline do auth-service
```

O que esperar (após ~4–6 min): run **parado no estágio 3**, passo
`Trivy FS - GATE CRITICAL/HIGH`:

```text
Security Scan -> Trivy FS - GATE CRITICAL/HIGH (CVE-2026-56854)
Total: 1 (UNKNOWN: 0, LOW: 0, MEDIUM: 0, HIGH: 1, CRITICAL: 0)
golang.org/x/crypto (golang)
╰─ CVE-2026-56854 (HIGH) → fix: 0.56.0
```

> **Para falar:** "O SCA comparou o `go.mod` com o banco de CVEs e achou uma vulnerabilidade
> **HIGH**. Pela regra do portão **CRITICAL/HIGH**, o pipeline parou aqui: não gerou imagem, não
> atualizou o GitOps."

**Passo 2 — revert manual (o mesmo pipeline passa):**

```bash
git pull --rebase origin main        # main pode ter avançado (bot do GitOps)

SHA_DEMO=$(git log origin/main --pretty=%H --grep='demo(sca)' -1)
git revert --no-edit "$SHA_DEMO"     # desfaz o downgrade (volta a versão saudável)
git push origin main                 # novo run: verde até o fim (inclui job 5 Update GitOps)
```

> **Para falar:** "A correção é um `git revert`. Porta fechada existe, mas a saída é rápida."

> **Dica:** os scripts `docs/scripts/provocar-sca.sh` + `reverter-sca.sh` são o **atalho**
> automatizado da mesma cena (commit + push + revert); servem de ensaio rápido antes da gravação.

**Cenas opcionais (se o tempo permitir)** — mesma mecânica:

| Script | O que muda | Bloqueio no estágio |
|---|---|---|
| `bash docs/scripts/provocar-sast.sh` | remove `#nosec G704` de `evaluation-service/evaluator.go` | Security Scan → `gosec` (4× SSRF, HIGH) |
| `bash docs/scripts/reverter-sast.sh` | `git revert` do demo | volta ao verde |
| `bash docs/scripts/provocar-lint.sh` | injeta variável não usada em `auth-service/main.go` | Lint → `golangci-lint` (`unused`) |
| `bash docs/scripts/reverter-lint.sh` | `git revert` do demo | volta ao verde |

> O compilador **aceita** a variável sem uso do demo de lint; só o linter reprova — a prova da
> diferença entre "compila" e "passa na análise estática".

**Como disparar um run "limpo" (sem quebrar nada):** não use `git commit --allow-empty` — o
**commit vazio não dispara** os workflows com filtro de `paths`. Use a aba **Actions** do GitHub
→ workflow do serviço → **Run workflow** (botão `workflow_dispatch`), ou um commit real tocando
o código do serviço.

---

## 3. Etapa 2 — GitOps + ArgoCD: o cluster converge sozinho

### 3.1 Entendendo em 1 minuto

A **entrega** (CD) não é feita com `kubectl` pelo pipeline. O CI faz **uma única coisa**: escrever
a **tag da imagem nova** num arquivo YAML do repositório GitOps
(`gitops/apps/<serviço>/kustomization.yaml`). O **repositório Git é a fonte de verdade** do que o
cluster deve ter; o **ArgoCD** é o agente que fica vigiando esse repositório e **converge o
cluster sozinho** quando o Git muda.

- `selfHeal`: se alguém mexer no cluster à mão, o ArgoCD **reverte** para o estado do Git.
- `prune`: recurso que saiu do Git é **removido** do cluster.

### 3.2 O que o job 5 do CI faz (e como provar)

Dentro do pipeline, o job `update-gitops` executa:

```bash
yq -i '.images[0].newTag = strenv("v1.0.0-<sha7>")' gitops/apps/<serviço>/kustomization.yaml
git commit -m "ci(<serviço>): bump image to v1.0.0-<sha7>" && git push
```

Para ver no terminal:

```bash
git log --oneline -5
# ci(evaluation-service): bump image to v1.0.0-xxxxxxx   <- commit AUTOMÁTICO do bot
# ci(auth-service): bump image to v1.0.0-xxxxxxx
# ...

git show HEAD --stat | head -10
# 1 file changed - só o kustomization.yaml do serviço

grep newTag gitops/apps/auth-service/kustomization.yaml
# newTag: v1.0.0-xxxxxxx
```

> **Para falar:** "Reparem no que o CI **não** fez: não rodou `kubectl`, não conectou no
> cluster. Mudou **uma linha** num YAML. Imagem nova no ECR → o GitOps aponta pra ela. Quem
> aplica isso no cluster é o ArgoCD."

### 3.3 Comandos para a demonstração

**Abrir a UI do ArgoCD:**

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Abre `https://localhost:8080` — usuário `admin`, senha impressa. O túnel evita expor o serviço em
público.

**Estado das Applications (no terminal, valida o que a UI mostra):**

```bash
kubectl get applications -n argocd
kubectl get pods -n feature-flags
```

### 3.4 O clímax: disparar o ciclo completo e ver o sync acontecer

O gatilho pode ser **qualquer push real na main** — o mais didático é reusar uma cena da Etapa 1
(ex.: `bash docs/scripts/provocar-lint.sh`). Com o pipeline correndo:

```bash
# Janela 1: acompanhando o deploy convergir
kubectl get applications -n argocd -w
kubectl rollout status deployment/auth-service -n feature-flags --timeout=180s
kubectl get pods -n feature-flags
```

A sequência para narrar:

1. O push dispara o pipeline (`build → lint → security → docker → update-gitops`).
2. O job `update-gitops` comita o **bump da tag** no `kustomization.yaml`.
3. Na UI do ArgoCD, a Application pisca **OutOfSync** e, segundos depois, volta a
   **Synced + Healthy** — sem clique nenhum.
4. `kubectl get pods` mostra o **rolling update** (pod novo subindo).

> **Para falar:** "Do meu push ao pod novo, **nenhuma ação manual**: o CI fez a imagem, escreveu
> a tag no Git, e o ArgoCD — que vigia sem parar — convergiu o cluster. O `kubectl` aqui é só
> para confirmar."

Não esqueça de fechar o demo aberto: `bash docs/scripts/reverter-lint.sh` (e deixar o run verde).

**Bônus opcional — provar o `selfHeal`** (faz e desfaz na hora):

```bash
kubectl scale deployment/evaluation-service -n feature-flags --replicas=5
# em segundos o ArgoCD devolve ao número do Git (desired), sem você tocar em nada
kubectl get deployments -n feature-flags
```

---

## 4. Encerramento

Para falar (3 frases):

- **IaC + backend remoto no S3**: infra inteira reconstruível a partir do código, estado com
  versionamento e lock.
- **CI + DevSecOps**: 5 estágios em que **SAST e SCA bloqueiam CRITICAL/HIGH** — provado num run
  real: vermelho pela vulnerabilidade, verde após o revert.
- **CD com GitOps + ArgoCD**: o CI só escreve uma **tag** no repositório; o ArgoCD **sincroniza o
  cluster automaticamente** com `selfHeal` e `prune` — drift zero.

| Entregável FIAP | Onde provar |
|---|---|
| Terraform com backend remoto | Apêndice B / plan–apply + bucket S3 versionado |
| Pipeline CI + DevSecOps (SAST/SCA bloqueando) | Etapa 1 (`_ci-reusable.yml`, run vermelho→verde) |
| CD/GitOps (tag no repo + ArgoCD sync automático) | Etapa 2 (kustomization bumped, UI ArgoCD, rollout) |

---

## Apêndice A — Cartões de defesa da banca

| Pergunta provável | Resposta pronta (curta) |
|---|---|
| O que é Infraestrutura como Código? | Infra descrita em arquivos versionados (Terraform `.tf`); o mesmo código cria, revisa e destrói ambientes — com revisão e rastreabilidade. |
| Por que backend remoto no S3? | O estado é a "foto" do ambiente. No S3 ele tem **versionamento** (rollback/auditoria), **SSE-S3** e **lock** (`use_lockfile`) — evita perda e `apply` concorrente. |
| SAST vs SCA? Por que CRITICAL/HIGH bloqueia? | SCA = vulnerabilidade nas **dependências** (CVE); SAST = bug no **código-fonte**. Bloquear CRITICAL/HIGH (SCA) / HIGH (SAST) impede vulnerabilidade conhecida de chegar ao cluster. |
| Como o CI acessa a AWS sem chave? | **OIDC**: o GitHub emite um token assinado; a AWS valida emissor/audience e entrega credencial **temporária** da role `togglemaster-github-ci-role`. Zero secret estático. |
| Por que o job de push do CI falhava / pipeline não iniciava? | Secret usado no caller mas **não declarado** no `workflow_call` → valor vazio ou `startup_failure`. Fix: declarar o secret no reutilizável + repassá-lo explicitamente. |
| O que é GitOps? | O Git é a **fonte de verdade** do estado desejado; mudanças entram por commit/PR e o agente (**ArgoCD**) converge o cluster. |
| O que fazem `selfHeal` e `prune`? | `selfHeal`: bagunça manual no cluster volta pro Git. `prune`: recurso fora do Git é removido. Juntos = drift zero. |
| Por que `use_lockfile` e não DynamoDB? | Terraform ≥ 1.10 tem lock nativo no S3 — sem recurso extra. |
| E se o ArgoCD não achar o repo? | Repo privado exige autorizar com token (`argocd repo add`); público não precisa. |
| Por que a tag `v1.0.0-<sha7>`? | Imagem **rastreável ao commit**: qualquer imagem no ECR responde "de qual push vim". |
| Commit vazio dispara o pipeline? | Não. Os workflows têm filtro de `paths`; para disparar use `workflow_dispatch` ou um commit real no código do serviço. |

---

## Apêndice B — Do zero (Terraform + ArgoCD + FASE 0)

> **Já executado no ambiente.** Mantido aqui para regravação completa ou para refazer em outro
> ambiente. Todos os comandos rodam da raiz do repositório.

### B.1 Bootstrap do backend remoto + leitura das variáveis

```bash
export AWS_PROFILE=tf
cp terraform/terraform.tfvars.example terraform/terraform.tfvars   # não versionado
bash terraform/scripts/bootstrap-state.sh                          # bucket S3: privado, versionado, criptografado
```

### B.2 Provisionar infraestrutura

```bash
cd terraform
terraform init
terraform plan -out=plan.out      # ~20 recursos: VPC, EKS, 3x RDS, Redis, DynamoDB, SQS, ECR x5, OIDC
terraform apply plan.out
cd ..
```

### B.3 Instalar o ArgoCD (2ª camada Terraform, estado próprio)

```bash
terraform -chdir=terraform/argocd-install init
terraform -chdir=terraform/argocd-install apply -auto-approve
```

### B.4 Conectar o kubectl + aplicar segredos e Applications

```bash
aws eks update-kubeconfig --name togglemaster-eks --region us-east-1

bash terraform/scripts/generate-k8s-secrets.sh     # Secrets a partir dos outputs do Terraform
kubectl apply -k gitops/base                       # namespace, SAs (IRSA), secrets, ingress, HPA, KEDA

kubectl apply -f gitops/argocd/applications/       # registra as 5 Applications
```

> **Nota:** se ainda houver pods em `ImagePullBackOff` (`imagePullPolicy: IfNotPresent` e imagem
> ausente no ECR), o primeiro push do CI resolve o ECR. Seed local opcional: build + push das 5
> imagens `:v1.0.0` no ECR, ou esperar o pipeline.

### B.5 Pré-requisitos de runtime da demonstração

Feitos neste ambiente e que **não devem ser refeitos** na gravação:

- **IRSA**: anotações `eks.amazonaws.com/role-arn` nos service accounts `analytics-service` e
  `evaluation-service` (pods precisam acessar SQS/DynamoDB); role do KEDA idem.
- **RDS**: tabelas criadas (`api_keys`, `flags`, `targeting_rules`) a partir dos
  `*/db/init.sql` + seed de API key de serviço (`SERVICE_API_KEY` no secret `app-secrets`).
- **Prova E2E**: `GET /evaluate?user_id=u1&flag_name=feature-a` responde e grava o evento no
  DynamoDB (`ToggleMasterAnalytics`).

### B.6 FASE 0 narrada (checklist do script)

```bash
AWS_PROFILE=tf bash docs/scripts/preparar-apresentacao.sh   # idempotente; pausa a cada fase
AWS_PROFILE=tf bash docs/scripts/preparar-apresentacao.sh --dry-run   # ensaio sem executar
```

| Fase | Comando | O que faz |
|---|---|---|
| 1/9 | `aws sts get-caller-identity` | confirma a conta `248530551510` |
| 2/9 | `cp terraform.tfvars.example terraform.tfvars` | variáveis por ambiente (não versionado) |
| 3/9 | `bash bootstrap-state.sh` | bucket S3 do estado: privado, versionado, criptografado |
| 4/9 | `terraform init` → `plan` → `apply` | provisiona a infra (~20 recursos) |
| 5/9 | `aws eks update-kubeconfig ...` | conecta o `kubectl` no EKS |
| 6/9 | `terraform -chdir=argocd-install ... apply` | instala o ArgoCD (2ª camada) |
| 7/9 | `generate-k8s-secrets.sh` + `kubectl apply -k gitops/base` | segredos + base (SAs, KEDA, ingress) |
| 8/9 | `terraform output -raw github_ci_role_arn` → secret `AWS_ROLE_ARN` | role que o CI assume via OIDC |
| 9/9 | `kubectl apply -f gitops/argocd/applications/` | registra as 5 Applications |
| Smoke | **push real** (ou `workflow_dispatch`) | dispara os 5 pipelines completos |

> ⚠️ Correção vs. versão antiga: o smoke **não** usa `git commit --allow-empty` — commit vazio
> **não dispara** os workflows (filtro de `paths`). Use o botão **Run workflow** nas Actions ou
> um push com mudança real.

**Checklist final (só grave com todos SIM):** 5 pipelines verdes (incl. `docker-build-scan-push`
e `update-gitops`) · ECR com `v1.0.0-<sha7>` e `:latest` · kustomizations bumped pelo bot ·
ArgoCD 5× Synced+Healthy · 9/9 pods Running em `feature-flags` · UI ArgoCD via port-forward.

---

## Apêndice C — Troubleshooting

| Sintoma | Causa | Solução |
|---|---|---|
| `Could not load credentials from any providers` (jobs 4–5) | Secret `AWS_ROLE_ARN` não criado ou valor vazio | FASE 0 passo 8: criar secret com `terraform output -raw github_ci_role_arn` |
| Run nem iniciou / `startup_failure` ao mexer em secrets | Secret usado no caller mas **não declarado** em `workflow_call.secrets` | Declarar `AWS_ROLE_ARN` no `on.workflow_call.secrets` do `_ci-reusable.yml` + repassar no caller |
| Run nem iniciou em push normal | Filtro de `paths` não bate (mudou só `docs/**`?) | Esperado. Para forçar: `workflow_dispatch` ou commit real no serviço |
| Commit vazio não dispara nada | `paths` ignora commits sem arquivos | Usar `workflow_dispatch` ou mudança real (scripts `provocar-*`) |
| Run **verde** mesmo com o `demo(sca)` aplicado | CVE-2026-56854 é **HIGH** e o gate SCA era só **CRITICAL** (`severity: CRITICAL` no `Trivy FS - GATE`) | Subir o portão para `severity: CRITICAL,HIGH` em `_ci-reusable.yml` (passo `Trivy FS - GATE CRITICAL/HIGH`) |
| Gate `CRITICAL,HIGH` deixa serviços verdes ficarem vermelhos | Python antigos carregam HIGHs legados (Flask 2.2.2/Werkzeug 2.2.2/gunicorn 20.1.0) e o `evaluation-service` usa `x/net` < 0.56 | Bump para versões corrigidas (`ci(<svc>): remediar CVEs HIGH legados`, `bump golang.org/x/net v0.56.0`) |
| `main local nao sincronizada` (scripts) | Bot do CI avançou `origin/main` (bump GitOps) | `git pull --rebase origin main` — cuidado em não desfazer demo aberto |
| `ja existe demo(...) pendente` | Provocação aberta em main | Rode o `reverter-*.sh` correspondente |
| Push rejeitado nos scripts | HTTPS sem credencial no WSL | Os scripts já usam `git@github.com:...` (SSH) |
| ArgoCD sem a Application | `applications/` não aplicado | `kubectl apply -f gitops/argocd/applications/` |
| ArgoCD não sincroniza repo privado | Sem token no repo | `argocd repo add ... --username <user> --password <PAT>` |
| Pods em `ImagePullBackOff` | Imagem não existe no ECR (primeira vez) | Deixar o pipeline ir até o job 4 (push no ECR) ou seed local `:v1.0.0` |

---

*Gerado a partir de `.github/workflows/_ci-reusable.yml` e `*-ci.yml`, `gitops/argocd/applications/*`,
`docs/scripts/*.sh`, do estado real do cluster (5 Applications Synced+Healthy, 9/9 pods Running)
e dos fixes de CI registrados em `a92a31f` (declaração de secret no `workflow_call`).*