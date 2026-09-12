# Roteiro detalhado de apresentação — ToggleMaster Fase 3

> **Teleprompter completo**: para cada passo há o **COMANDO** exato, o que ele faz
> (explicação de 1 linha), o **flag a flag**, o que **vai aparecer** na tela e a **FALA**
> palavra por palavra. Use `[colchetes]` como marcação de cena: `[pausa]`, `[apontar X]`,
> `[mostrar Y]`.
>
> **Duração:** ~20 min de vídeo + folga para as explicações. **Janelas:** terminal (esq) +
> navegador (dir). Grave por cena — Ctrl-C no terminal pausa o take.

---

## Índice

1. Como usar esta guia
2. Introdução (0:00–1:30)
3. Cena 1 — Infraestrutura como Código / Terraform (1:30–6:00)
4. Cena 2 — Pipelines CI + DevSecOps (6:00–11:30)
5. Cena 3 — CD/GitOps: a tag que o CI escreve (11:30–15:00)
6. Cena 4 — ArgoCD: o cluster converge sozinho (15:00–19:00)
7. Encerramento (19:00–20:00)
8. Apêndice A — Cartões de defesa da banca
9. Apêndice B — FASE 0 narrada (gravar do zero)
10. Apêndice C — Troubleshooting

---

## 1. Como usar esta guia

- **Material de pré-gravação:** `AWS_PROFILE=tf bash docs/scripts/preparar-apresentacao.sh`
  e o checklist do final dele devem estar **100% SIM** antes de gravar.
- **Cenas de falha:** são feitas com os scripts `docs/scripts/provocar-{sca,sast,lint}.sh`
  (vermelho) e `reverter-{sca,sast,lint}.sh` (verde). Eles já fazem commit + push + abrem o
  acompanhamento do run.
- **Layout:** Janela 1 = terminal (git repo root); Janela 2 = browser (GitHub Actions,
  Console AWS, ArgoCD). OBS/QuickTime com as duas janelas lado a lado.
- **Convenções dos blocos:**

| Bloco | O que contém |
|---|---|
| **COMANDO** | O comando exato, como será digitado |
| **O QUE ELE FAZ** | Explicação em 1 linha |
| **FLAG A FLAG** | Detalhe de cada parte/flag do comando |
| **O QUE VAI APARECER** | Resultado esperado / onde clicar |
| **FALA** | Narração pronta (português), palavra por palavra |
| **TRANSIÇÃO** | Texto para emendar a próxima cena |

---

## 2. Introdução (0:00–1:30)

**[tela: capa com logo ToggleMaster — "Fase 3: IaC + DevSecOps + GitOps"]**

### FALA
> "Olá! Hoje eu apresento a **Fase 3** do **ToggleMaster**, nosso sistema de *feature flags*
> com cinco microserviços: **auth, flag, targeting, evaluation e analytics**, todos em um
> monorepo."
>
> `[pausa]`
>
> "O problema que a Fase 3 resolve é o clássico **infraestrutura e entrega à mão**: cluster,
> bancos, filas, imagens e deploy configurados um por um, sem rastreabilidade e sem porta de
> saída. A proposta é transformar **tudo isso em código** e provar na prática três entregáveis:"
>
> - "**1 — Infraestrutura como Código com Terraform**, com backend remoto no S3 com
>   versionamento e lock.";
> - "**2 — Pipeline de CI com DevSecOps**: build, lint, **SAST e SCA** que **bloqueiam**
>   vulnerabilidade **CRITICAL/HIGH** antes de chegar no Docker e no deploy;"
> - "**3 — CD com GitOps + ArgoCD**: o pipeline escreve uma **tag** no repositório e o
>   **ArgoCD sincroniza o cluster automaticamente**."
>
> `[pausa]`
>
> "Vou mostrar cada um na prática, com os comandos, o que eles fazem e o resultado no
> ambiente. Vamos começar pela infraestrutura."

### TRANSIÇÃO
> "Primeiro, a base de tudo: a infraestrutura como código na AWS."

---

## 3. Cena 1 — Infraestrutura como Código / Terraform (1:30–6:00)

**[Janela 1: editor aberto no `terraform/`; Janela 2: Console AWS]**

### 3.1 Abrindo o monorepo e o projeto Terraform

#### COMANDO
```bash
cd <caminho-do-repo>
tree terraform terraform/modules -d
```

#### O QUE ELE FAZ
Mostra a estrutura de diretórios do projeto Terraform: config principal, módulos por serviço
AWS e a segunda camada (`argocd-install`).

#### FLAG A FLAG
- `tree <dir1> <dir2>`: exibe a árvore de diretórios (a flag `-d` mostra **só diretórios**, sem
  arquivos, para a tela ficar limpa).

#### O QUE VAI APARECER
```
terraform/
├── main.tf            # composição dos módulos
├── versions.tf        # backend remoto S3 + providers
├── variables.tf
├── outputs.tf
├── scripts/
├── argocd-install/    # 2ª camada: instala o ArgoCD no EKS
└── modules/
    ├── networking/  ├── eks/  ├── rds/  ├── elasticache/
    ├── dynamodb/    ├── sqs/  ├── ecr/  └── github_oidc/
```

#### FALA
> "O Terraform recebe o nome de *Infraestrutura como Código* porque a infra inteira — rede,
> cluster, bancos, fila, cache, registros ECR e até a integração de CI — está descrita em
> arquivos `.tf` versionados aqui no Git."
>
> `[apontar a árvore]`
>
> "Há um `main.tf` que **compõe módulos**: cada módulo cuida de um recorte (`networking`,
> `eks`, `rds`, `elasticache`, `dynamodb`, `sqs`, `ecr`, `github_oidc`). Dá para reusar,
> isolar e revisar cada peça."

### 3.2 O backend remoto (por que o estado nunca fica local)

**[abrir `terraform/versions.tf`]**

#### O QUE MOSTRAR
As linhas 13–22 de `versions.tf`:

```hcl
terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket       = "togglemaster-tfstate-248530551510"
    key          = "togglemaster/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
```

#### FLAG A FLAG
- `required_version = ">= 1.10.0"`: exige Terraform ≥ 1.10 (necessário para o lock nativo do S3).
- `backend "s3"`: o **estado do Terraform** (o "mapa" do que existe na AWS) fica num **bucket S3**.
  `bucket` = nome do bucket; `key` = "pasta" do estado; `region` = us-east-1.
- `encrypt = true`: criptografia ao gravar o estado.
- `use_lockfile = true`: **lock** feito pelo próprio S3 (evita dois `apply` simultâneos) — sem
  precisar de tabela DynamoDB (recurso novo do Terraform ≥ 1.10).

#### FALA
> "O Terraform guarda o **estado** — a foto do que já foi criado — num **backend remoto no
> S3**, nunca na máquina de quem roda. Isso dá **versionamento**, **criptografia** e **lock**:
> se eu rodar `apply` duas vezes ao mesmo tempo, o segundo espera o primeiro. O bucket é
> criado automaticamente pelo `bootstrap-state.sh`, que veremos já, já."

### 3.3 Configurando as variáveis

#### COMANDO
```bash
export AWS_PROFILE=tf
cp ../terraform/terraform.tfvars.example ../terraform/terraform.tfvars
```

*(rodar dentro de `docs/scripts/` — ou, equivalentemente, `cp terraform/terraform.tfvars.example terraform/terraform.tfvars` na raiz)*

#### O QUE ELE FAZ
Habilita o perfil `tf` da CLI AWS e materializa o arquivo de variáveis a partir do exemplo.

#### FLAG A FLAG
- `export AWS_PROFILE=tf`: toda chamada `aws` desta sessão autentica com o perfil `tf`
  (credenciais da conta `248530551510`, us-east-1). Sem expor chave nenhuma no terminal.
- `cp <exemplo> <tfvars>`: o `.tfvars` é onde ficam valores que **variam por ambiente** (CIDRs,
  instância de banco, etc.) — **não é versionado** (está no `.gitignore`). Por isso o repositório
  guarda um **exemplo** e você copia para o seu ambiente.

#### O QUE VAI APARECER
Bloco de cabeçalho + as variáveis preenchidas (project_name `togglemaster`, `vpc_cidr`,
subnets, `ecr_repository_names` com os 5 serviços, etc.).

#### FALA
> "Cada ambiente tem valores próprios. A boas prática é commitar um **`.tfvars.example`** e
> copiá-lo para o `.tfvars` local — assim o time sabe quais variáveis existem sem vazar valores
> sensíveis."

### 3.4 botando o backend remoto de pé

#### COMANDO
```bash
bash terraform/scripts/bootstrap-state.sh
```

#### O QUE ELE FAZ
Cria, **uma única vez**, o bucket S3 de estado e o deixa seguro: bloqueio de acesso público,
versionamento, criptografia SSE-S3 (AES256) e, opcionalmente, replica a config para outra
conta.

#### FLAG A FLAG (por partes, visíveis no script)
- `aws sts get-caller-identity --query Account --output text`: confirma em que conta estamos
  (espera `248530551510`).
- `aws s3api create-bucket --bucket togglemaster-tfstate-248530551510 --region us-east-1`:
  cria o bucket (us-east-1 não exige `LocationConstraint`).
- `aws s3api put-public-block ... BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true`:
  **bloqueia qualquer acesso público** ao estado.
- `aws s3api put-bucket-versioning --versioning-configuration Status=Enabled`:
  **versionamento** — cada versão do estado fica gravada (rollback e auditoria).
- `aws s3api put-bucket-encryption ... SSEAlgorithm=AES256`: **criptografia padrão** no bucket.

#### O QUE VAI APARECER
```
==> Backend remoto: s3://togglemaster-tfstate-248530551510
==> Garantindo bucket ... (ou "bucket ja existe")
==> Bloqueio de acesso publico...
==> Versionamento...
==> Criptografia padrao (SSE-S3)...
Backend pronto.
```

#### FALA
> "Numa única execução esse script deixou o bucket de estado **privado, versionado e cripto-
> grafado**. A partir daqui, qualquer `terraform init` na máquina de quem participar encontra o
> mesmo estado no S3."

### 3.5 terraform init / plan / apply

#### COMANDO
```bash
cd terraform
terraform init
terraform plan -out=plan.out
terraform apply plan.out
```

#### O QUE ELE FAZ
(`init`) baixa os providers e conecta no backend S3; (`plan`) calcula o "plano" de mudanças e
grava num arquivo; (`apply`) executa o plano, criando/alterando a infra.

#### FLAG A FLAG
- `terraform init`: lê `versions.tf`, baixa `hashicorp/aws ~> 5.70` e `hashicorp/random ~> 3.6`,
  e conecta no **backend S3** (cria lock file do estado).
- `terraform plan -out=plan.out`: mostra a árvore de mudanças (~20 recursos ao criar) e **salva**
  num arquivo — garante que o `apply` rode exatamente o que foi aprovado visualmente.
- `terraform apply plan.out`: aplica o plano salvo; ao final imprime os **outputs** (VPC ID,
  endpoints RDS, ARN da role OIDC etc.).

#### O QUE VAI APARECER (plan)
```
An execution plan has been generated and is shown below.
Terraform will perform the following actions:

  # module.networking.aws_vpc.this will be created
  # module.networking.aws_subnet.public[0] ...
  # module.eks.aws_eks_cluster.this will be created
  # module.rds.aws_db_instance.this[0] ... (x3)
  ...
Plan: 20 to add, 0 to change, 0 to destroy.
```

#### O QUE VAI APARECER (apply)
Resumo `Apply complete! Resources: 20 added, 0 changed, 0 destroyed.` + outputs
(ex.: `kubectl_config_command`, `github_ci_role_arn`).

#### FALA
> "Reparem: o **plan** não muda nada — ele só calcula. Aqui eu vejo **20 recursos a criar**,
> desde VPC até o cluster EKS, e só aplico depois de revisar. O `apply` então executa.
> **Rastreabilidade**: tudo o que existe na AWS vem exatamente deste código."

### 3.6 Provando no AWS Console

**[Janela 2 → AWS Console, região us-east-1]**

#### O QUE MOSTRAR (navegar pelos serviços)
1. **VPC** → `togglemaster-vpc` (CIDR, subnets públicas/privadas, IGW, route tables).
2. **EKS** → cluster `togglemaster-eks` (versão, node group, endpoint público).
3. **RDS** → **3** instâncias PostgreSQL (`togglemaster-auth`, `togglemaster-flag`,
   `togglemaster-targeting`), subnets privadas.
4. **ElastiCache** → Redis `togglemaster-redis`.
5. **DynamoDB** → tabela `ToggleMasterAnalytics`.
6. **SQS** → fila + DLQ (dead-letter queue).
7. **ECR** → 5 repositórios `togglemaster-{auth,flag,targeting,evaluation,analytics}`.
8. **IAM** → role `togglemaster-github-ci-role` (usada pelo OIDC do GitHub Actions).

#### FALA
> "É só conferir no Console: a VPC com suas subnets, o cluster EKS, os três bancos
> PostgreSQL, o Redis, a tabela DynamoDB, a fila SQS com DLQ e os cinco registros ECR. Tudo
> isso nasceu do mesmo `terraform apply` — nada foi clicado à mão."

### 3.7 Conectando o kubectl no cluster

#### COMANDO
```bash
aws eks update-kubeconfig --name togglemaster-eks --region us-east-1
```

#### O QUE ELE FAZ
Baixa as credenciais do cluster EKS e atualiza o `~/.kube/config` local — a partir daqui o
`kubectl` fala com o cluster.

#### FLAG A FLAG
- `--name togglemaster-eks`: qual cluster.
- `--region us-east-1`: região. (Usa a mesma credencial da CLI — sem chave a mais.)

#### O QUE VAI APARECER
```
Added new context arn:aws:eks:us-east-1:248530551510:cluster/togglemaster-eks to /home/.../.kube/config
```

#### FALA
> "Com o cluster no ar, conecto o `kubectl`. A credencial é federada pela nossa sessão AWS —
> o Kubernetes não exige senha nova."

### TRANSIÇÃO
> "Infra pronta. Agora a parte que garante **código bom e seguro antes de virar imagem e ir para
> produção**: os pipelines de CI com DevSecOps."

---

## 4. Cena 2 — Pipelines CI + DevSecOps (6:00–11:30)

**[Janela 2 → GitHub → seu repositório → Actions → pipeline "auth CI"]**

### 4.1 O caller vs. o workflow reutilizável

#### O QUE MOSTRAR
`.github/workflows/auth-ci.yml` (linhas 12–38):

```yaml
name: "auth CI"
on:
  push:
    branches: [main]
    paths:
      - "auth-service/**"
      - ".github/workflows/auth-ci.yml"
      - ".github/workflows/_ci-reusable.yml"
  pull_request:
    branches: [main]
    paths:
      - "auth-service/**"

permissions:
  contents: write
  id-token: write

jobs:
  ci:
    name: "Pipeline auth"
    uses: ./.github/workflows/_ci-reusable.yml
    with:
      service-name: auth-service
      working-directory: auth-service
      language: go
      go-version-file: auth-service/go.mod
      ecr-repository: togglemaster-auth
```

#### FLAG A FLAG
- `on.push/pull_request`: quando dispara — push na main **ou** PR para main.
- `paths:` **filtros de caminho**: o pipeline só roda quando os arquivos do `auth-service/` (ou os
  próprios workflows) mudam. As outras 4 services têm o mesmo padrão.
- `permissions.contents: write` + `id-token: write`: necessário para o CI commitar no GitOps e
  **assumir a role da AWS via OIDC** (sem secret estático).
- `uses: ./.github/workflows/_ci-reusable.yml`: delega tudo para o workflow **reutilizável**
  ("não repita o mesmo YAML 5 vezes").

#### FALA
> "Cada serviço tem um workflow **caller** de 10 linhas; a lógica vive no `_ci-reusable.yml`.
> Reparem nos **filtros de path**: mudou só a `flag-service`, só o pipeline dela roda."

### 4.2 O grafo dos 5 jobs

#### O QUE MOSTRAR
Na aba **Actions** do `auth CI`, o grafo:

```
1. Build & Unit Test  →  2. Lint  →  3. Security Scan (SAST & SCA)
                                          ↓
                    5. Update GitOps (nova tag)  ←  4. Docker Build & Scan & Push
```

#### FALA
> "O CI tem **5 jobs encadeados**. Em **PR** rodam os três primeiros (build, lint, security);
> em **push na main** rodam os cinco — porque só na main a imagem vai pro ECR e o GitOps é
> atualizado. Qualquer falha **interrompe** o pipeline: nada de imagem nem deploy com problema."

### 4.3 Job 1 — Build & Unit Test

#### O QUE MOSTRAR
`_ci-reusable.yml` linhas 74–131: `go build -v ./...`, `go test -v ./...` (Go) e o equivalente
Python (`pip install`, `pytest` ou `compileall`).

#### FLAG A FLAG
- `actions/setup-go@v5` com `go-version-file:`: instala **exatamente a versão do go.mod** e usa
  cache do `go.sum`.
- `go build -v ./...`: compila todos os pacotes (falhou = problema real, não só de estilo).
- `go test -v ./...`: roda os testes unitários.

#### FALA
> "O primeiro portão é o clássico: se **não compila** ou **teste falha**, nem sai do lugar."

### 4.4 Job 2 — Lint (estilo + correção)

#### COMANDO (no terminal local, útil p/ mostrar o que o CI faz)
```bash
docker run --rm -v "$PWD":/src -w /src/auth-service golang:1.26-alpine \
  sh -c "go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.13.2 && \
  /root/go/bin/golangci-lint run --timeout=5m"
```

*(o CI roda o mesmo passo em `_ci-reusable.yml:157-158`)*

#### O QUE ELE FAZ
Roda o linter Go (golangci-lint) com dezenas de verificações de **estilo e bugs prováveis**.

#### FLAG A FLAG
- `go install .../golangci-lint/v2/cmd/golangci-lint@v2.13.2`: instala **versão fixada** (v2.13.2).
  O **`/v2`** no caminho é o sufixo de módulo da v2 — detalhe que já quebrou o CI e foi corrigido.
- `run --timeout=5m`: analisa o pacote atual.

#### FALA
> "O linter roda **antes** do security scan. A lógica é: qualidade mínima de **código** primeiro.
> Para os serviços em Python o padrão é `flake8` (erros fatais) + `pylint` (`--errors-only`)."

### 4.5 Job 3 — Security Scan: SAST e SCA (o coração do DevSecOps)

#### O QUE MOSTRAR
`_ci-reusable.yml` linhas 187–250. Explicar as **duas palavras**:

- **SCA — Software Composition Analysis**: olha as **dependências** (bibliotecas no `go.mod`,
  `requirements.txt`, `package-lock`) contra bancos de CVE.
- **SAST — Static Application Security Testing**: analisa o **código-fonte** (padrões de
  vulnerabilidade).

#### FLAG A FLAG
- **Trivy FS — relatório completo** (linhas 199–207): `continue-on-error: true`, `scanners:
  vuln,secret,misconfig`, todas as severidades — **visibilidade**, não bloqueia.
- **Trivy FS — GATE CRITICAL** (linhas 211–219): `severity: CRITICAL`, `exit-code: "1"`,
  `ignore-unfixed: true` — **qualquer CRITICAL = pipeline vermelho**.
- **gosec (Go)** (linhas 232–242): `-severity high` — **HIGH bloqueia** (gosec não tem CRITICAL;
  HIGH é o topo).
- **bandit (Python)** (linhas 245–250): `-r . -lll` — **HIGH bloqueia**.

#### FALA
> "Aqui está a diferença do DevSecOps: **segurança dentro do pipeline, como portão**. Primeiro
> um scan **informativo** (para o dev ver a imagem completa); depois o **bloqueio**: severidade
> **CRITICAL** para dependências e **HIGH** para código, com `exit-code 1`. Vulnerabilidade
> crítica encontrada? O pipeline **para** — nem chega a gerar a imagem."

### 4.6 A prova ao vivo: cena de falha SCA

> **Pré-requisito:** FASE 0 concluída e tudo verde. Local: raiz do repo, branch main, push SSH.

#### COMANDO
```bash
bash docs/scripts/provocar-sca.sh
```

#### O QUE ELE FAZ
Faz **downgrade** da dependência `golang.org/x/crypto` para a versão **v0.20.0** (que tem o
**CVE-2026-56854, CRITICAL**), comita como `demo(sca): ...`, faz push e abre o acompanhamento do
run.

#### FLAG A FLAG (do que acontece por trás)
- `docker run ... golang:1.26-alpine sh -c "go mod edit -require=golang.org/x/crypto@v0.20.0 && go mod tidy"`:
  edita o `go.mod` e **regenera o `go.sum` dentro de um container Go** — se fosse só editar o
  texto, o `go.sum` ficaria inconsistente e o próprio build falharia antes da segurança.
- `require_main_clean` / `require_no_open_demo` (em `docs/scripts/lib.sh`): só roda em main
  sincronizada e sem outro demo pendente.
- `remote_push`: `git push git@github.com:maiconjfa/techchallenge2-projetofiap.git main:main`
  (push via **SSH**, necessário neste WSL).
- `show_run`: usa `gh run watch` para acompanhar o **log ao vivo** — ideal para o vídeo.

#### O QUE VAI APARECER (no terminal e no GitHub)
```
==> Push enviado. O pipeline deve parar (run VERMELHO) em:
    Security Scan -> Trivy FS - GATE CRITICAL (CVE-2026-56854)
==> Run no GitHub Actions: https://github.com/<repo>/actions/runs/<id>
```
No log do job `Security Scan`, passo **Trivy FS - GATE CRITICAL**:

```text
Total: 1 (UNKNOWN: 0, LOW: 0, MEDIUM: 0, HIGH: 0, CRITICAL: 1)
golang.org/x/crypto (golang)
╰─ CVE-2026-56854 (CRITICAL) → fix: 0.56.0
```

#### FALA
> "Simulando um dev que baixou uma dependência antiga. O **SCA** comparou o `go.mod` com o banco
> de CVEs e encontrou o **CVE-2026-56854, CRITICAL**, no `x/crypto`. Pela regra de bloqueio, o
> pipeline **parou aqui** — não gerou imagem, não atualizou o GitOps, não chegou a lugar
> nenhum."

### 4.7 A correção: de vermelho para verde

#### COMANDO
```bash
bash docs/scripts/reverter-sca.sh
```

#### O QUE ELE FAZ
Reverte o commit `demo(sca)` (devolve o `x/crypto` para a versão fixa), faz push e acompanha o
novo run — que deve ficar **verde**.

#### O QUE VAI APARECER
`git revert` do SHA + run verde atravessando `Security Scan` → `Docker Build & Scan & Push` →
`Update GitOps`.

#### FALA
> "A correção é um `git revert` — a dependência volta para a versão saudável. **O mesmo
> pipeline** agora passa. É essa a dinâmica do DevSecOps: a porta existe, mas a saída é rápida."

### 4.8 Cenas opcionais (se o tempo permitir) — SAST e Lint

Cada uma com `provocar-X.sh` → run vermelho → `reverter-X.sh` → verde. Mesma mecânica do SCA.

#### Opcional 1 — SAST (gosec, SSRF)

#### COMANDO
```bash
bash docs/scripts/provocar-sast.sh
```

#### O QUE ELE FAZ
Remove os **4 comentários `// #nosec G704`** de `evaluation-service/evaluator.go` (linhas
126/129/159/162). Sem o *nosec*, o **gosec** volta a acusar **4× G704 (SSRF, HIGH)** — o código
faz requests para URLs com origem externa (mitigado pela função `sanitizeFlagName`, que valida
`^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}$`).

#### O QUE VAI APARECER (no log)
```text
[evaluation-service/evaluator.go:126] - G704 (Medium-High): Potential HTTP request made with
variable url
```
(mensagens idênticas nas linhas 126, 129, 159 e 162; exit 1 → run vermelho)

#### FALA
> "SAST de código-fonte: aqui o **gosec** flagrou **4 trechos de SSRF** — o endpoint do
> `evaluation-service` monta um request com URL vinda de fora. O `#nosec` que mascarava foi
> removido só para a demonstração. Quem validou aquele arco de código foi um humano, com
> sanitização de entrada — não o scanner. HIGH bloqueia: vermelho."

#### Opcional 2 — Lint (golangci-lint `unused`)

#### COMANDO
```bash
bash docs/scripts/provocar-lint.sh
```

#### O QUE ELE FAZ
Adiciona uma **variável de pacote não usada** (`var demoUnused`) em `auth-service/main.go`. O
**compilador aceita** (build passa), mas o **golangci-lint** reprova (`unused`).

#### O QUE VAI APARECER (no log)
```text
main.go:XX:2: var demoUnused is unused (unused)
```

#### FALA
> "Este exemplo mostra a diferença entre **compilar** e **passar por análise estática**: o Go
> aceita uma variável sem uso, mas o lint **não**. Código morto entra no repositório? Aqui ele
> entra só para ser barrado e corrigido."

### TRANSIÇÃO
> "Com as portas de build, lint e segurança abertas, a imagem vai para o ECR e agora começa a
> **entrega** — mas note: o pipeline **não** usa `kubectl` nenhum."

---

## 5. Cena 3 — CD/GitOps: a tag que o CI escreve (11:30–15:00)

**[Janela 2: log do job 4 e job 5 do pipeline verde; Janela 1: terminal no repo]**

### 5.1 O job 4 — imagem criada, escaneada e enviada ao ECR

#### O QUE MOSTRAR
`_ci-reusable.yml` linhas 255–309 (job `docker-build-scan-push`):

- `IMAGE_TAG="v1.0.0-${GITHUB_SHA::7}"`: etiqueta determinística a partir do SHA do commit.
- `docker build` com as tags `<tag>` e `:latest`.
- **Trivy Image — GATE CRITICAL** (linhas 284–291): a imagem **já construída** também é
  escaneada; CRITICAL bloqueia o push.
- `configure-aws-credentials@v4` com `role-to-assume: ${{ secrets.AWS_ROLE_ARN }}`: **OIDC** —
  o Actions **assume uma role** da AWS sem ter chave: o GitHub emite um token, a AWS valida o
  emissor e troca por credenciais temporárias.
- `amazon-ecr-login@v2` + `docker push` para `248530551510.dkr.ecr.us-east-1.amazonaws.com/togglemaster-<serviço>`.

#### FALA
> "A imagem é criada, **escaneada de novo** (agora na forma de imagem) e só então enviada ao
> **ECR**. A autenticação é por **OIDC**: o runner assume a role `togglemaster-github-ci-role`
> com token do GitHub — **nenhuma chave token secret fica no repositório**. A tag é
> `v1.0.0-<7 caracteres do SHA>`: rastreável ao commit exato."

### 5.2 O job 5 — o único deploy é escrever uma tag no GitOps

#### O QUE MOSTRAR
`_ci-reusable.yml` linhas 314–353 (job `update-gitops`):

```bash
export NEW_TAG="v1.0.0-<sha7>"
yq -i '.images[0].newTag = strenv(NEW_TAG)' \
    gitops/apps/<service>/kustomization.yaml

git commit -m "ci(<service>): bump image to ${NEW_TAG}"
git push
```

#### FLAG A FLAG
- `yq -i '.images[0].newTag = strenv(NEW_TAG)'`: atualiza **o campo `newTag` do Kustomize**
  com a nova imagem (respeitando o valor como string via `strenv`).
- O caminho é **uma única linha por serviço**: `gitops/apps/<service>/kustomization.yaml`.
- `git pull --rebase origin main` antes do push: serializa os 5 pipelines simultâneos
  (job `update-gitops` tem `concurrency: group: gitops-update`).

#### PROVA NO TERMINAL
```bash
git log --oneline -3
# ci(analytics-service): bump image to v1.0.0-xxxxxxx   <- commit recente do bot

git show HEAD --stat | head        # só 1 arquivo mudou

cat gitops/apps/auth-service/kustomization.yaml | grep newTag
#   newTag: v1.0.0-xxxxxxx
```

#### O QUE VAI APARECER (log no GitHub)
```
Atualizando gitops/apps/auth-service/kustomization.yaml -> v1.0.0-xxxxxxx
1 file changed, 1 insertion(+)
```

#### FALA
> "Reparem no que o pipeline **não** fez: não rodou `kubectl`, não conectou no cluster. Ele fez
> uma mudança **de uma linha** num arquivo YAML do repositório **GitOps** — que nada mais é que
> a **fonte de verdade do estado desejado**. Imagem nova no ECR? O GitOps agora aponta para ela.
> Quem convergirá o cluster é o próximo personagem: o ArgoCD."

### TRANSIÇÃO
> "Para fechar o ciclo, vamos ver o ArgoCD transformando esse YAML em pods rodando."

---

## 6. Cena 4 — ArgoCD: o cluster converge sozinho (15:00–19:00)

### 6.1 Descobrindo a senha do admin e abrindo a UI

#### COMANDO
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

#### O QUE ELE FAZ
Recupera a **senha inicial** que o ArgoCD gerou na instalação e abre um túnel local para a UI
em: https://localhost:8080.

#### FLAG A FLAG
- `-n argocd`: namespace da instalação (Feita pela 2ª camada Terraform em `terraform/argocd-install/`).
- `-o jsonpath='{.data.password}' | base64 -d`: extrai o campo `password` do secret e **decodifica
  base64** — é assim que o k8s guarda segredos.
- `port-forward svc/argocd-server 8080:443`: o `svc` do ArgoCD serve HTTPS na 443; o túnel expõe
  pouco em `localhost:8080` — sem precisar expor o serviço publicamente.

#### O QUE VAI APARECER
A senha impressa no terminal + no browser (https://localhost:8080) a tela de login do ArgoCD.

#### FALA
> "O ArgoCD foi instalado como **segunda camada do Terraform**: a primeira provisou o cluster; a
> segunda instala o ArgoCD dentro dele (cada uma com seu próprio estado no S3 — aqui em
> `togglemaster/argocd.tfstate`). A senha inicial vem de um secret do Kubernetes; em produção
> troca-se por senha própria. O `port-forward` me dá a UI sem expor nada em público."

### 6.2 As 5 Applications e o sync automático

#### LOGIN
Usuário `admin` + senha impressa.

#### O QUE MOSTRAR
- **Applications** com os 5 serviços: `auth-service`, `flag-service`, `targeting-service`,
  `evaluation-service`, `analytics-service` — todos **Synced** e **Healthy**.
- Em Settings → Repositories: aponta para `https://github.com/maiconjfa/techchallenge2-projetofiap`.
- O caminho de cada app (`gitops/apps/<service>`) e o destino (`namespace feature-flags`).

#### O QUE MOSTRAR (o YAML, em `gitops/argocd/applications/auth-service.yaml`)
```yaml
source:
  repoURL: https://github.com/maiconjfa/techchallenge2-projetofiap.git
  targetRevision: main
  path: gitops/apps/auth-service

destination:
  server: https://kubernetes.default.svc
  namespace: feature-flags

syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
```

#### FLAG A FLAG
- `source.repoURL / targetRevision / path`: **de onde** o ArgoCD lê o estado desejado (repo
  GitOps, branch `main`, pasta do serviço).
- `destination.namespace: feature-flags`: **para onde** aplica (e cria o namespace com
  `CreateNamespace=true`).
- `syncPolicy.automated.prune`: remove o que existe no cluster mas saiu do Git (drift negativo).
- `syncPolicy.automated.selfHeal`: se alguém apagar/alterar no cluster à mão, o ArgoCD **volta**
  ao estado do Git.
- `retry.limit/backoff`: em caso de falha de sync, tenta de novo com backoff (10s → 2m, até 5x).

#### FALA
> "Cada Application é um contrato: **'o que eu quero'** vive no Git (na pasta `gitops/apps/...`),
> **'onde'** é o namespace `feature-flags`. Com **automated + prune + selfHeal**, o ArgoCD fica
> vigiando o repositório: mudou o Git, ele converge; alguém mexeu à mão no cluster, ele
> **reverte** para o Git — eu chamo isso de *fonte de verdade única*."

### 6.3 O clímax: disparar o ciclo completo e ver o sync acontecer

**[Janela 1: terminal com `kubectl`; Janela 2: UI do ArgoCD aberta na Application escolhida]**

#### COMANDO (no repo local)
```bash
bash docs/scripts/provocar-lint.sh
```

*(qualquer push na main serve — o demo de lint é só o gatilho mais rápido; o CI fará o bump no
GitOps automaticamente)*

#### EM SEGUIDA, AGUARDANDO O PIPELINE:
```bash
kubectl rollout status deployment/auth-service -n feature-flags --timeout=180s
kubectl get pods -n feature-flags
```

#### O QUE VAI ACONTECER (em sequência, para narrar)
1. O push dispara o pipeline (`build → lint → security → docker → update-gitops`).
2. O job `update-gitops` comita o bump da tag no `kustomization.yaml`.
3. Na UI do ArgoCD, a Application muda para **OutOfSync** e, segundos depois, volta a **Synced**
   + **Healthy** — **sem nenhum clique**.
4. `kubectl get pods` mostra o Deployment **rolling** (pod novo subindo, pod antigo saindo).

#### FALA
> "Olha a prova do ciclo completo: o CI detectou minha mudança, construiu a imagem, o
> `update-gitops` escreveu a tag nova no repositório GitOps, e o ArgoCD — que nunca para de
> vigiar — viu `OutOfSync` e **sincronizou sozinho**. O `kubectl` aí do lado é só para
> confirmar: o deployment está fazendo o **rolling update** naquele momento. Do meu push ao pod
> novo, **nenhuma ação manual**."

### 6.4 Bônus de defesa — como o ArgoCD ficou sabendo da repo?

#### FALA + COMANDO (se o repo GitOps for privado)
> "Num repositório privado, você autoriza o ArgoCD uma vez com um token:"
```bash
argocd repo add https://github.com/maiconjfa/techchallenge2-projetofiap \
  --username <user> --password <PAT>
```

(*repo público não precisa — nosso caso de demonstração.*)

### TRANSIÇÃO
> "Fechando: o que entregamos e como responder a banca."

---

## 7. Encerramento (19:00–20:00)

### FALA
> "Resumindo o que foi provado na prática:"
>
> - "**IaC com Terraform e backend remoto**: o estado no S3 com versionamento, criptografia e
>   lock; infra inteira reconstruível a partir do código;"
> - "**CI + DevSecOps**: pipeline em 5 estágios onde **SAST e SCA bloqueiam CRITICAL/HIGH** —
>   e demonstramos isso num run vermelho-real e a correção para verde;"
> - "**CD com GitOps + ArgoCD**: o CI só escreve uma **tag** no repositório GitOps, e o ArgoCD
>   **sincroniza o cluster automaticamente** com `selfHeal` e `prune`."
>
> "Tudo isso somado ao roadmap que o projeto exige: **networking completo, EKS, 3 bancos RDS,
> Redis, DynamoDB, SQS e 5 registros ECR** — provisionados e atualizados de forma **rastreada,
> segura e reprodutível**. Obrigada(o)!"

#### BLOCOS MERCADOLÓGICOS (tela final)
| Entregável FIAP | Onde provar |
|---|---|
| 1. Terraform com backend remoto | Cena 1 (`versions.tf`, bucket, plan/apply) |
| 2. Pipeline CI + DevSecOps (SAST/SCA bloqueando) | Cena 2 (`_ci-reusable.yml`, run vermelho→verde) |
| 3. CD/GitOps (tag no repo + ArgoCD sync automático) | Cenas 3–4 (`kustomization` bumped, UI ArgoCD) |

---

## Apêndice A — Cartões de defesa da banca

| Pergunta provável | Resposta pronta (curta) |
|---|---|
| O que é Infraestrutura como Código? | Infra descrita em arquivos versionados (Terraform `.tf`); o mesmo código cria, revisa e destrói ambientes — com revisão PR e rastreabilidade. |
| Por que backend remoto? | Estado é "foto" do ambiente: se perder/ficar num único laptop, o Terraform não sabe o que existe. S3 com **versionamento** (rollback/auditoria), **SSE-S3** e **lock** (`use_lockfile`) evitam perda e `apply` concorrente. |
| Qual a diferença de SAST vs SCA? + por que CRITICAL bloqueia? | SCA = vírus nas **dependências** (CVE); SAST = bug nos **seus fontes**. Bloqueio em CRITICAL (SCA) / HIGH (SAST) impede que vulnerabilidade conhecida chegue ao cluster — barato corrigir antes, caríssimo depois. |
| Como o CI acessa a AWS sem chave? | **OIDC**: o GitHub emite um token assinado; a AWS valida emissor/audience e troca por credencial **temporária** da role `togglemaster-github-ci-role`. Nenhum secret estático no repo. |
| O que é GitOps? | O repositório Git é a **fonte de verdade** do estado desejado; mudanças entram via commit/PR e o agente (**ArgoCD**) converge o cluster. |
| O que fazem `selfHeal` e `prune`? | `selfHeal`: máquina-bagunça no cluster volta pro Git. `prune`: recurso que saiu do Git é removido. Juntos = **drift zero**. |
| Por que `use_lockfile` e não DynamoDB? | Terraform ≥ 1.10 tem lock nativo no S3 (`use_lockfile=true`) — sem recurso extra, mais simples. |
| E se o ArgoCD não achar o repo? | Repo privado exige autorizar com token (`argocd repo add`); público não precisa. |
| Por que a tag `v1.0.0-<sha7>`? | Imagem **rastreável ao commit**: qualquer imagem no ECR responde "de qual push vim". |

---

## Apêndice B — FASE 0 narrada (gravar do zero)

Use quando quiser gravar **desde o início**. Rode dentro de `docs/scripts/`:

```bash
AWS_PROFILE=tf bash preparar-apresentacao.sh
```

Para ensaio sem executar: `AWS_PROFILE=tf bash preparar-apresentacao.sh --dry-run`.

| Fase | Comando (via script) | O QUE ELE FAZ | FALA curta |
|---|---|---|---|
| 1/9 | `aws sts get-caller-identity --query Account --output text` | Confirma a conta `248530551510` | "Garanto que estou na conta certa antes de qualquer coisa." |
| 2/9 | `cp terraform.tfvars.example terraform.tfvars` | Materializa variáveis por ambiente | "O `.tfvars` não é versionado; o exemplo documenta as variáveis." |
| 3/9 | `bash terraform/scripts/bootstrap-state.sh` | Cria bucket S3 seguro p/ o estado | "Backend remoto: privado, versionado e criptografado." |
| 4/9 | `terraform init` → `plan -out=plan.out` → `apply plan.out` | Baixa providers, calcula e aplica plano (~20 recursos) | "O plan mostra a lista; o apply executa. Infra nasce do código." |
| 5/9 | `aws eks update-kubeconfig --name togglemaster-eks --region us-east-1` | Conecta o `kubectl` no cluster | "Agora o `kubectl` fala com o EKS." |
| 6/9 | `terraform -chdir=argocd-install init` → `apply -auto-approve` | 2ª camada Terraform: instala ArgoCD no cluster | "Camada separada com estado próprio: cluster tem que existir antes." |
| 7/9 | `bash generate-k8s-secrets.sh` + `kubectl apply -k gitops/base` | Gera Secrets (senhas RDS etc.) a partir dos outputs e aplica | "Segredos vêm dos outputs do Terraform; o `secrets.yaml` é gitignored." |
| 8/9 | `terraform output -raw github_ci_role_arn` → secret `AWS_ROLE_ARN` (gh ou manual) | Entrega à AWS a role que o Actions vai assumir via OIDC | "Sem essa role, os jobs de docker e GitOps não têm permissão." |
| 9/9 | `kubectl apply -f gitops/argocd/applications/` | Registra as 5 Applications no ArgoCD | "Anuncio ao ArgoCD onde está cada estado desejado." |
| Smoke | `git commit --allow-empty -m 'ci: smoke test'` + push | Dispara os 5 pipelines completos | "Confirmação final: tudo verde antes de gravar." |

**Checklist final (só grave com todos SIM):** 5 pipelines verdes (incl. docker + gitops) ·
ECR com imagem `v1.0.0-<sha7>` e `:latest` · kustomizations bumped · ArgoCD 5× Synced+Healthy ·
5 pods Running em `feature-flags` · acesso à UI ArgoCD via port-forward.

---

## Apêndice C — Troubleshooting

| Sintoma | Causa | Solução |
|---|---|---|
| `Could not load credentials from any providers` (jobs 4–5) | Secret `AWS_ROLE_ARN` não criado | FASE 0 passo 8: criar secret com o ARN de `terraform output -raw github_ci_role_arn` |
| Run nem iniciou | Filtros de `paths` não batem | Mudou só `docs/**`? Nenhum pipeline deve disparar mesmo — ok. |
| `Node.js 20 actions are deprecated` (warn) | Aviso informativo do runner | Ignorar. |
| `main local nao sincronizada` (scripts) | Bot do CI avançou `origin/main` (bump GitOps) | `git pull --rebase origin main` — mas cuidado: nunca desfaça um demo aberto |
| `ja existe demo(...) pendente` | Uma provocação ficou aberta | Rode o `reverter-*.sh` correspondente |
| Push rejeitado no `provocar-*` | HTTPS sem credencial no WSL | Os scripts já usam `git@github.com:...` (SSH). Use a mesma para o clone |
| ArgoCD sem a Application | `applications/` não aplicado | `kubectl apply -f gitops/argocd/applications/` |
| ArgoCD não sincroniza repo privado | Repositório privado sem token | `argocd repo add ... --username <user> --password <PAT>` |
| Dois demos ao mesmo tempo | `concurrency` serializa por serviço (+`gitops-update`) | Rode os demos em sequência, um por vez |

---

*Gerado a partir de `docs/scripts/*.sh`, `.github/workflows/_ci-reusable.yml`,
`terraform/{versions,main,outputs}.tf`, `gitops/argocd/applications/*.yaml` e do histórico real
dos fixes `ceade19`, `317cf38`, `03abd9c`.*