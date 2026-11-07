# Roteiro de Demonstração — ToggleMaster (≤ 25 min)

> **Formato:** cada bloco traz **tela/link/comandos (evidência)** e **Falar:** com roteiro detalhado em fala natural. Execute comandos ao vivo para evidência em tempo real.
> **Regra de ouro:** **não sincronizar** `opentelemetry-collector` nem forçar syncs que revertam drifts controlados (preserva Service Map/Datadog e estabilidade da demo).

---

## 0) Introdução — abertura (45–60 s)

**Tela:** slide/tela inicial com **ToggleMaster** + os 5 microserviços; abas preparadas (ArgoCD, Grafana, Datadog, PagerDuty, Slack).

**Falar:** “Bom dia, meu nome é **[seu nome]** e eu vou apresentar o **ToggleMaster**, nossa plataforma de *feature flags* em arquitetura de microserviços. O sistema tem cinco serviços que trabalham juntos: o `auth-service`, responsável pela autenticação e validação de identidade; o `flag-service`, que guarda o cadastro e o estado das feature flags; o `targeting-service`, que aplica as regras de segmentação e define para qual público uma flag deve ser ativada; o `evaluation-service`, que é o serviço central desta demonstração, porque recebe a requisição de avaliação e consulta os outros serviços para decidir o valor final da flag para um usuário; e o `analytics-service`, que trata os eventos gerados pelo uso das flags, inclusive consumindo mensagens de fila.

O objetivo desta demonstração não é apenas mostrar telas, e sim **comprovar, em ambiente operando**, todos os requisitos do projeto. Vou evidenciar: primeiro, que a infraestrutura foi provisionada com **Infra como Código usando Terraform na AWS/EKS** e que a operação da stack é feita por **GitOps com ArgoCD**, tudo versionado no repositório; segundo, uma stack completa de observabilidade com **métricas no Grafana a partir de um dashboard customizado**, **logs centralizados no Loki** e o **OpenTelemetry Collector** recebendo e roteando a telemetria dos cinco serviços; terceiro, que o **APM está ativo no Datadog**, com o **Service Map** mostrando dependências entre serviços e um **trace distribuído detalhado**, gerado a partir de uma requisição de teste que executarei ao vivo; e, por fim, a prova de resiliência operacional: vou provocar um **incidente proposital**, mostrar o **alerta em estado Firing**, a abertura do incidente e a notificação nos canais configurados (**PagerDuty e Slack**), e a execução automática do **Self-Healing**, com o pod reiniciando no terminal como ação corretiva.

Organizei a apresentação em blocos: começo pelas evidências no **repositório**, passo para a **visão geral do cluster e do ArgoCD**, demonstro **métricas, logs e o funcionamento do OTel Collector**, entro no **APM e tracing distribuído no Datadog** e encerro com a **prova real de incidente e auto-remediação**.”

**Contexto (se perguntarem):** EKS `togglemaster-eks` (AWS profile `tf`, `us-east-1`, conta `248530551510`), namespaces `feature-flags, observability, argocd, datadog, self-healing`. **IP antigo `54.224.13.189` não é válido** — usar IPs de nó atuais ou `port-forward`. **Drifts conhecidos (não sincronizar na demo):** `opentelemetry-collector` com ajuste *live* (conector/estatísticas Datadog) divergente do Helm/GitOps — **não sync**; `self-healing-webhook` **1/1 Running/funcional**, mas ArgoCD pode exibir **`Degraded/Progressing`** por RS antigo/tag divergente (`v1.0.0` no manifest × `latest` em execução), auto-sync desativado; `PrometheusRule auth-service-5xx-alert` live usa expressão legada (`http_requests_total`) vs Git (`otel_traces_spanmetrics_calls_total`) — para garantir Firing use o **Caminho B** (Bloco 5).

---

## 1) Preparação — 10–15 min antes (com tudo logado)

### 1.1 Abas e terminais
| # | Aba/Janela | Link/Comando | Credencial/Obs. |
|---|---|---|---|
| T1 | Terminal — comandos | `cd /home/maicon/projetos/postech/fase2/tech-challenge && export AWS_PROFILE=tf AWS_REGION=us-east-1` | repo + AWS |
| T2 | Terminal — watch | `kubectl -n feature-flags get pods -l app=auth-service -w` | pod reiniciando (Bloco 5) |
| T3 | Terminal — logs self-healing | `kubectl -n self-healing logs deploy/self-healing-webhook -f` | prova webhook |
| A1 | ArgoCD | `https://34.229.45.189:31473` (ou `18.206.239.193:31473` / `54.211.248.7:31473` / `3.224.114.200:31473`) | HTTPS, cert self-signed. **Fallback:** `kubectl -n argocd port-forward svc/argocd-server 8443:443` → `https://127.0.0.1:8443` |
| A2 | Grafana — Dashboard | `http://34.229.45.189:30124/d/togglemaster-overview/togglemaster-overview` | `admin` / `prom-operator`. **Fallback:** `kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80` → `http://127.0.0.1:3000/d/togglemaster-overview/togglemaster-overview` |
| A3 | Grafana — Explore (Loki) | `http://34.229.45.189:30124/explore` (ou `127.0.0.1:3000/explore`) | datasource **Loki** (hard refresh se não aparecer) |
| A4 | Grafana — Alerting | `http://34.229.45.189:30124/alerting/list` | regras/estados |
| A5 | Datadog — Service Map (US5) | `https://us5.datadoghq.com/apm/map?env=demo` | `env:demo`, **Past 1 hour** |
| A6 | Datadog — Traces client | `https://us5.datadoghq.com/apm/traces?query=env%3Ademo+service%3Aevaluation-service+operation_name%3A*client*` | deps evaluation-service |
| A7 | Datadog — Traces (5 svc) | `https://us5.datadoghq.com/apm/traces?query=env%3Ademo+service%3A%28auth-service+OR+flag-service+OR+targeting-service+OR+evaluation-service+OR+analytics-service%29` | visão ampla |
| A8 | PagerDuty | Incidents do serviço ToggleMaster | incidente aberto (Bloco 5) |
| A9 | Slack/Discord | Canal `#togglemaster-alerts` | notificação `[CRÍTICO]` |
| A10 | VS Code / GitHub | `https://github.com/maiconjfa/techchallenge2-projetofiap.git` (local T1) | evidência de código |

**NodePorts:** Grafana `30124`, ArgoCD `31473`, avaliação `30286`, auth `31318`, flag `31302`, targeting `31670`, analytics `31946`. Se bloqueio/firewall → **port-forward**.

### 1.2 Tráfego inicial (popular métricas, Loki, Datadog)
```bash
# T1 — validação
curl -s -X POST "http://34.229.45.189:30286/evaluate?user_id=prep&flag_name=beta-feature" || \
curl -s -X POST "http://127.0.0.1:18004/evaluate?user_id=prep&flag_name=beta-feature"

# rajada
for i in $(seq 1 30); do
  curl -s -o /dev/null -X POST "http://34.229.45.189:30286/evaluate?user_id=demo$i&flag_name=beta-feature" || true
done
```
**Fallback port-forward (terminal separado):** `kubectl -n feature-flags port-forward deploy/evaluation-service 18004:8004` → `curl -s -X POST "http://127.0.0.1:18004/evaluate?user_id=demo&flag_name=beta-feature"`

**Falar:** “Antes de iniciar, já deixei o ambiente preparado para as evidências aparecerem em tempo real, com ArgoCD, Grafana, Datadog, PagerDuty e Slack abertos e o terminal autenticado no cluster com o perfil AWS correto. Agora executo requisições no `POST /evaluate`, variando o usuário, porque essa chamada percorre o fluxo principal do ToggleMaster e gera telemetria real: **spans de tracing** para o Datadog, **métricas derivadas** consultadas pelo Grafana no Prometheus e **logs** consultáveis no Loki. Com esse tráfego inicial, ao abrir os painéis veremos dados atuais do ambiente, não telas vazias.”

---

## 2) Código-fonte no repositório (2–3 min) — evidência versionada

### 2.1 Repositório, branch e histórico (T1/A10)
```bash
git remote -v
git branch -vv
git log --oneline -8
git status -sb
```
**Falar:** “Começo pelo código-fonte porque a avaliação exige comprovar que a solução está versionada e reproduzível. Mostro o repositório `techchallenge2-projetofiap` com o *remote*, a branch e o histórico recente de commits, evidenciando que mudanças de infraestrutura, observabilidade, instrumentação e automação foram registradas no controle de versão. O que demonstrarei no cluster não depende de ajustes manuais escondidos: deriva de artefatos no Git — manifests de GitOps, configuração do OpenTelemetry Collector, código instrumentado e a automação de Self-Healing.”

### 2.2 IaC, GitOps e stack de observabilidade (inclui OTel Collector) (A10)
**Abrir (caminho + trechos):** `terraform/`; `gitops/observability/otel-collector/{application.yaml,values.yaml}`; `gitops/observability/kube-prometheus-stack/application.yaml`, `loki/application.yaml`, `promtail/application.yaml`; `gitops/observability/dashboards/json/togglemaster-overview.json`; `gitops/observability/alerting/{auth-5xx-alert.yaml,prometheus-rules.yaml,alertmanager-config.yaml|alertmanagerconfig.yaml}`; `gitops/self-healing/*.yaml`.

**Falar:** “Na pasta `terraform` está a **Infra como Código**, que define a base na AWS — cluster **EKS**, rede e identidade como **IAM, OIDC e IRSA** — para workloads e monitoramento rodarem com permissões controladas; é a fundação do ambiente. Em `gitops` declaro o estado desejado do cluster e o **ArgoCD** observa esses manifests e reconcilia o Kubernetes com o Git, integrando versionamento e operação contínua.

Em `gitops/observability` destaco o **OpenTelemetry Collector**, coração da coleta: `application.yaml` e `values.yaml` declaram como ele é implantado e configurado. Ele atua como **hub central**: os cinco microserviços enviam telemetria **OTLP** (4317/4318); o Collector recebe nos *receivers*, aplica *processors* — `memory_limiter` (evita picos de memória), `batch` (agrupa com eficiência) e `resource` (enriquece com atributos padronizados como ambiente `demo` e namespace `feature-flags`) — e **roteia** para os destinos corretos: *traces* para o **Datadog** (APM e Service Map); métricas, incluindo **spanmetrics**, para **Prometheus/Grafana** e também Datadog; e logs para o **Loki**. Isso desacopla as aplicações dos backends.

Ainda em `gitops/observability`, o dashboard customizado `ToggleMaster - Overview` está versionado em JSON e os alertas/roteamento no Alertmanager também; em `gitops/self-healing` estão deploy, serviço e RBAC do componente de auto-remediação. Monitoramento, alerta e resposta automática também são código no repositório.”

### 2.3 Instrumentação OpenTelemetry nas aplicações (A10)
**Abrir (destacar trechos OTLP/`service.name`/tracer-span e, no evaluation, cliente `otelhttp`/propagação):** `evaluation-service/{otel.go,handlers.go}`; `flag-service/{otel.py,app.py}`; `targeting-service/otel.py`; `analytics-service/{otel.py,app.py}`; `auth-service/otel.go`.

**Falar:** “A observabilidade está **instrumentada dentro das aplicações**. Todos os cinco serviços integram **OpenTelemetry** e exportam via **OTLP** para o Collector, identificando `service.name` e o ambiente `demo`, permitindo filtrar e correlacionar no Grafana e no Datadog.

Destaco o `evaluation-service` (Go), que materializa o **tracing distribuído**: além do span do servidor no `POST /evaluate`, ele faz chamadas HTTP para `flag-service` e `targeting-service` com instrumentação de cliente e **propagação de contexto**, gerando **spans de cliente** com atributos como `span.kind=client`, `peer.service` (destino), `http.url` e `http.status_code`. Essa combinação permite ao Datadog montar o **trace distribuído ponta a ponta** e inferir dependências no **Service Map**.

Os demais serviços complementam o fluxo: `flag-service` e `targeting-service` respondem estado/regras; `analytics-service` processa eventos (inclusive cenários com fila SQS) emitindo spans correlacionáveis; `auth-service` fornece validação de identidade. Integração clara: aplicações geram telemetria, Collector recebe e distribui, e Prometheus/Grafana, Loki e Datadog transformam em visualização, consulta e diagnóstico.”

### 2.4 Automação de Self-Healing — código e manifests (A10)
**Abrir:** `apps/self-healing-webhook/{app.py,Dockerfile,requirements.txt,README.md}` (rotas `/webhook`, `/healthz`, chamada `rollout restart`); `gitops/self-healing/{deployment.yaml,service.yaml,rbac.yaml,application.yaml}` (SA/Role/RoleBinding, imagem/namespace).

**Falar:** “A resposta a incidentes não pode depender de ação manual. O **Self-Healing** é um serviço em **Flask** (`apps/self-healing-webhook`) que expõe `GET /healthz` (saúde para o Kubernetes) e `POST /webhook`, que recebe alertas do **Alertmanager**.

A lógica é objetiva e segura: ao chegar um alerta, identifica o serviço afetado e, se permitido, chama a **API do Kubernetes** para executar `kubectl rollout restart` do *deployment* correspondente no namespace `feature-flags`, forçando recriação controlada dos pods. Esse poder não é irrestrito: em `gitops/self-healing` declaro **ServiceAccount**, **Role** e **RoleBinding** com permissões mínimas no namespace correto (menor privilégio), além de *deployment* e *service* versionados. Cadeia completa: Prometheus detecta, Alertmanager dispara/roteia, webhook recebe e o Kubernetes executa a remediação automaticamente.”

---

## 3) Visão geral — EKS (IaC) + ArgoCD (GitOps) com a nova stack (≈3 min)

### 3.1 Cluster EKS operando (T1)
```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl get ns
kubectl -n feature-flags get deploy,pods,svc
kubectl -n observability get pods
kubectl -n argocd get pods
kubectl -n datadog get pods
kubectl -n self-healing get deploy,pods,svc
```
**Evidência:** nós **Ready**; 5 deployments/pods **Running** em `feature-flags`; pods de observabilidade (collector, grafana, prometheus, alertmanager, loki, promtail); ArgoCD/Datadog ativos; `self-healing-webhook` **1/1 Available/Running**.

**Falar:** “Agora mostro o ambiente **efetivamente em operação**. `kubectl cluster-info` confirma o cluster correto e `get nodes -o wide` mostra os nós do **Amazon EKS `togglemaster-eks`** *Ready* — cluster provisionado por **Terraform (IaC)**.

Em `feature-flags` vemos os cinco microserviços rodando (`auth, flag, targeting, evaluation, analytics`), cada um com sua responsabilidade (autenticação, estado de flags, segmentação, avaliação e eventos). Em `observability` está a nova stack: **OpenTelemetry Collector** (ingestão/roteamento), **kube-prometheus-stack** (Prometheus, Alertmanager, Grafana) e **Loki/Promtail** (logs). Em `argocd` e `datadog` os componentes de GitOps e APM ativos. Em `self-healing`, o `self-healing-webhook` aparece **1/1 disponível e Running**, pronto para receber alertas.

Isso comprova a integração das camadas: Terraform cria a base, ArgoCD mantém o alinhamento ao Git, os microserviços geram telemetria continuamente e a stack transforma dados em métricas, logs, traces, alertas e ações corretivas.”

### 3.2 ArgoCD (GitOps) — aplicações, função, integração e status (A1)
**Link:** `https://34.229.45.189:31473` (fallback `https://127.0.0.1:8443`). **Clique:** lista de *Applications* → colunas **Sync/Health** → abrir `kube-prometheus-stack` → **Tree** (Deployment/Service/ConfigMap/PrometheusRule) → **App Details** (Source repo/path/revision/chart). Voltar e abrir `loki`, `opentelemetry-collector`, `self-healing-webhook`. (Aceitar cert self-signed.)

**Resumo por aplicação (aponte na tela):**
| App | Função (componente) | Integração | Status/observação |
|---|---|---|---|
| **`loki`** | Agrega/armazenamento de **logs** (Loki + Promtail), consultas **LogQL** | logs dos pods/OTel → **Loki** → **Grafana Explore** | geralmente **Synced/Healthy** |
| **`kube-prometheus-stack`** | **Métricas e alertas**: Prometheus, Alertmanager, Grafana, exporters, CRDs (`ServiceMonitor/PrometheusRule/AlertmanagerConfig`) | Prometheus faz *scrape* do OTel `:8889` (spanmetrics) e cluster → Grafana visualiza → Prometheus avalia regras → Alertmanager envia PagerDuty/Slack/webhook | **Healthy** (pode *OutOfSync* por drift/CRDs ao vivo, sem indisponibilidade) |
| **`opentelemetry-collector`** | **Hub OTLP** (4317/4318), *processors* (`memory_limiter,batch,resource`), **spanmetrics**, roteamento | apps → Collector → *traces* **Datadog APM** (Service Map/traces) → *métricas* **Prometheus/Grafana** (+Datadog) → *logs* **Loki** | pode **Unknown/Healthy** (`ComparisonError` Helm/remoto) + **ajuste live** p/ Service Map — **não sincronizar** |
| **`self-healing-webhook`** | **Auto-remediação** Flask (`POST /webhook`, `/healthz`) → `rollout restart` em `feature-flags` com **RBAC** mínimo | Alertmanager → webhook → **Kubernetes API** reinicia Deployment; PagerDuty/Slack em paralelo | **Synced**, pode **Degraded/Progressing** (abaixo); **pod 1/1 Running e funcional** |

**Falar (visão geral):** “No **ArgoCD** demonstro o **GitOps**, que mantém o cluster alinhado ao versionado. Cada *Application* representa recursos da stack. Em `kube-prometheus-stack`, a **Tree** mostra hierarquicamente os objetos gerenciados (Deployments, Services, ConfigMaps e CRDs como PrometheusRules) e **App Details** mostra a origem (repo, path/revisão ou chart Helm). Essa rastreabilidade é a essência do GitOps: estado desejado declarado no repositório e ArgoCD reconciliando.

Pelas aplicações: **Loki** agrega e consulta logs; **kube-prometheus-stack** concentra métricas, alertas e visualização; **opentelemetry-collector** é o hub central de telemetria roteando para os destinos corretos; **self-healing-webhook** automatiza a correção quando um alerta dispara. Fluxo integrado: serviços emitem telemetria, Collector distribui, Prometheus/Grafana monitoram, Loki armazena logs e o self-healing executa resposta automática.”

**Falar (status de `self-healing-webhook` + “enquanto não utilizado”):** “Sendo transparente: o ArgoCD mostra `self-healing-webhook` **sincronizado**, mas a saúde pode aparecer **Degraded ou Progressing**. Isso vem do estado de *rollout* no Kubernetes: existe um **ReplicaSet antigo** associado a tag divergente — o manifest referencia `v1.0.0` enquanto a execução estabilizou com outra tag (`latest`) — e esse RS antigo acaba recriado/pendente em **ImagePullBackOff/ErrImagePull**. Ao mesmo tempo, o **ReplicaSet ativo mantém 1 pod Running, 1/1 pronto**, e o *Deployment* está disponível. O alerta de saúde é da réplica antiga do rollout, mas o **serviço já está no ar e funcional**: responde em `/healthz`, o *Service* está publicado internamente e o RBAC está aplicado. Para estabilidade, o *auto-sync* está temporariamente desativado; a correção definitiva é alinhar a tag da imagem no Git/ECR/Deployment e reativar a sincronização.

Sobre o que ele fez **enquanto não era utilizado** (sem incidente): ele não executa ação destrutiva nem `rollout restart` por iniciativa própria; opera em modo **passivo e reativo**, que é o esperado. O container permanece em execução, responde a *liveness/readiness* via `/healthz`, aguarda requisições HTTP no `POST /webhook` do Alertmanager e mantém carregadas as permissões RBAC. A ação corretiva só ocorre quando um alerta roteado chega com serviço válido. Ou seja, mesmo sem incidente, cumpria **prontidão operacional** — e, ao ser acionado, executa a remediação e registra em logs (Bloco 5).”

**Falar (nota `opentelemetry-collector`):** “O `opentelemetry-collector` pode aparecer *Unknown* ou com divergência na renderização do chart. Há um **ajuste aplicado ao vivo** (conector/estatísticas para APM no Datadog) que garante o **Service Map** em `env:demo`. Esse ajuste ainda não foi consolidado da mesma forma no GitOps/Helm remoto, então **não vou sincronizar** agora para preservar a telemetria da demonstração.”

---

## 4) Métricas, Logs e OTel (≈7–8 min)

### 4.1 Métricas — dashboard customizado no Grafana (A2, T1)
**Link:** `http://34.229.45.189:30124/d/togglemaster-overview/togglemaster-overview` (`admin`/`prom-operator`, fallback `127.0.0.1:3000/...`). **Clique:** **Last 15 minutes** → **Refresh** → navegar painéis (namespace + requisições/erros por serviço) → em painel HTTP: **⋮ → Inspect → Query** (mostrar `otel_traces_spanmetrics_calls_total`, labels `service_name`, `span_kind="SPAN_KIND_SERVER"`, `http_status_code`) → voltar, gerar `curl /evaluate` em **T1**, **Refresh** (variação em tempo real).

**Falar:** “Estou no **Grafana** no dashboard **ToggleMaster - Overview**, que não é um painel manual perdido no cluster: está **versionado no repositório** em JSON no GitOps, reforçando reprodutibilidade.

Observo duas perspectivas: saúde/recursos do namespace e, principalmente, **requisições e erros por serviço** a partir de métricas derivadas de *tracing*. Em *Inspect → Query* vejo `otel_traces_spanmetrics_calls_total` segmentada por `service_name`, tipo de span e status HTTP — evidência de que o Grafana consulta o **Prometheus** via **PromQL**, e o Prometheus coleta essas métricas do **OpenTelemetry Collector**.

Integração: microserviços emitem *spans* com OpenTelemetry; o Collector processa com **spanmetrics**, transformando rastreamento em métricas de taxa, erro e duração (modelo **RED**); expõe no endpoint de *scrape* `:8889` e o Prometheus, via *ServiceMonitor* da stack, coleta periodicamente; o Grafana visualiza. Para provar tempo real, gero novas requisições `/evaluate` e atualizo: as séries variam, confirmando coleta, armazenamento, consulta e visualização ponta a ponta.”

### 4.2 Logs — busca e correlação no Loki (A3, T1)
**Link:** `http://34.229.45.189:30124/explore` (ou `127.0.0.1:3000/explore`). **Clique:** data source **Loki** → query `{namespace="feature-flags"}` (**Last 15 minutes**) → **Run query** → expandir linhas (timestamp, labels `namespace/pod/container/app`) → gerar 1–2 `curl /evaluate` e consultar novamente. Opcional: `{namespace="feature-flags", app="evaluation-service"}`.

**Falar:** “Agora demonstro **logs centralizados** no Grafana *Explore* com **Loki**. Seleciono o Loki e executo **LogQL** `{namespace="feature-flags"}`, retornando registros dos containers dos microserviços nesse namespace.

Ao expandir, vejo mensagem e metadados (horário, pod, container, *labels*), fundamentais para **correlacionar** com métricas e, adiante, com traces: posso recortar por serviço, período e componente, acelerando investigação.

A integração envolve coleta de logs dos containers (stack **Loki/Promtail**) e o pipeline tratado na arquitetura com o **OpenTelemetry Collector**; o Grafana consulta/visualiza no Loki. Disparo requisições `/evaluate` e repito a consulta: novas entradas aparecem, confirmando coleta ativa.”

**Contingência (se datasource não aparecer):** “Faço *hard refresh* ou novo login: o datasource **Loki** foi configurado/validado para `http://loki.observability.svc.cluster.local:3100`. Como evidência adicional, posso listar pods/serviço do Loki em `observability` e repetir a consulta quando visível.”

### 4.3 OpenTelemetry Collector — roteamento com evidência (A10, T1)
**Abrir:** `gitops/observability/otel-collector/values.yaml` (intenção versionada) **+** terminal:
```bash
kubectl -n observability get pods -l app.kubernetes.io/name=opentelemetry-collector
kubectl -n observability get svc otel-collector-opentelemetry-collector
kubectl -n observability logs deploy/otel-collector-opentelemetry-collector --tail=20
# Config efetiva (live) — receivers/exporters/pipelines
kubectl -n observability get cm otel-collector-opentelemetry-collector -o jsonpath='{.data.relay}'
```

**Falar:** “O **OpenTelemetry Collector** é ponto central da observabilidade. Mostro a configuração versionada e o estado efetivo no cluster, porque ele é o **hub de ingestão e roteamento** de toda a telemetria.

No terminal confirmo pod em execução e *Service* interno; logs indicam saúde. Exibo o ConfigMap com a configuração efetiva (evidência direta do roteamento).

Em etapas: **receivers** recebem via **OTLP** (gRPC/HTTP, 4317/4318), padrão aberto independente de fornecedor. **Processors**: `memory_limiter` protege contra picos de memória, `batch` agrupa para eficiência e `resource` padroniza atributos (`deployment.environment=demo`, namespace `feature-flags`) para filtrar/correlacionar. **Métricas a partir de traces**: com **spanmetrics** — e, no estado live desta demo, com conector/estatísticas necessárias ao APM do Datadog — transforma *spans* em métricas, viabilizando taxa/erros no Grafana sem implementar tudo manualmente.

**Exporters/pipelines (roteamento):** *traces* → **Datadog** (APM, Service Map, traces distribuídos e métricas derivadas); métricas OTLP + *spanmetrics* → **Prometheus** (scrape `:8889`, consumido pelo Grafana) e também Datadog; *logs* → **Loki**. Resumo: `auth, flag, targeting, evaluation, analytics` enviam ao **OTel Collector**, que distribui para **Datadog APM**, **Prometheus/Grafana** e **Loki** — desacoplando instrumentação e destinos, com flexibilidade e escalabilidade.”

---

## 5) APM e Tracing — Datadog (≈4–5 min)

### 5.1 Service Map — dependências a partir de traces (A5, apoio A7)
**Link:** `https://us5.datadoghq.com/apm/map?env=demo` (US5, **`env:demo`**, **Past 1 hour**, Refresh). **Evidência:** grafo com os 5 serviços; arestas **`evaluation-service → flag-service`** e **`→ targeting-service`**. Se demorar: gere tráfego (T1) e atualize; use **A7**.

**Falar:** “No **APM do Datadog** demonstro observabilidade distribuída no nível de requisições. Estou no **US5**, filtrando `env:demo` e última hora para dados recentes.

O **Service Map** **não é desenhado manualmente**: é construído automaticamente a partir dos *traces*. Chamadas instrumentadas entre serviços geram dependências no grafo.

Vejo os serviços do ToggleMaster e o fluxo-chave: **`evaluation-service`** depende de **`flag-service`** e **`targeting-service`** — funcionalmente, para avaliar uma flag ele consulta estado e regras de segmentação. O `analytics-service` aparece no ecossistema (eventos; conforme volume/operação podem surgir dependências inferidas, como fila).

O mapa dá visão de **topologia e impacto**: com latência/erro, identifico rapidamente por onde o fluxo passa e quais dependências contribuem. Resultado da integração: instrumentação OTel nas aplicações → envio ao Collector → processamento/exportação ao Datadog com contexto para inferência de dependências.”

### 5.2 Requisição de teste + Trace distribuído detalhado (T1 → A6)
```bash
curl -s -X POST "http://34.229.45.189:30286/evaluate?user_id=apresentacao&flag_name=beta-feature"
# fallback (port-forward 18004:8004):
# curl -s -X POST "http://127.0.0.1:18004/evaluate?user_id=apresentacao&flag_name=beta-feature"
```
**Clique (A6):** query `env:demo service:evaluation-service operation_name:*client*` → Refresh → trace recente → **Flame graph/Waterfall**. Abrir span servidor **`POST /evaluate`** (`evaluation-service`) e spans **client** `GET /flags/beta-feature`, `GET /rules/beta-feature` (destinos `flag-service`, `targeting-service`, **HTTP 200**). Em cada span mostrar: `service`, `env=demo`, `span.kind=client` (filhos), `http.method`, `http.status_code`, `http.url`, `peer.service`/destino, **duração**.

**Falar:** “Gero uma **requisição de teste ao vivo**: `POST /evaluate` com `user_id=apresentacao` e `flag_name=beta-feature`, operação real pelo serviço de avaliação.

No Datadog *Traces* (filtro `env:demo`, operações de cliente do `evaluation-service`) abro o trace mais recente. O *flame graph/waterfall* evidencia o **tracing distribuído** em uma linha de tempo única.

No topo, o span do **`evaluation-service`** no `POST /evaluate`. A partir dele, chamadas para decidir a flag: consulta **`flag-service`** (estado) e **`targeting-service`** (regras), cada uma como **span de cliente** com HTTP 200.

Nos detalhes, confirmo correlação técnica: `env=demo`, *client* nas saídas, método/URL, status e identificação do destino (`peer.service`), além da duração. A **propagação de contexto do OpenTelemetry** transmite trace/span pai-filho entre processos, encadeando tudo no mesmo trace — permitindo responder onde está latência/erro e qual dependência falhou.”

---

## 6) Incidente e Self-Healing — Prova Real (≈5–6 min)

> **Objetivo:** problema proposital → **Firing** → PagerDuty/Slack → **Self-Healing** (pod reinicia). Webhook/roteamento (`AlertmanagerConfig alertmanager-selfhealing`) ativos. `AuthServiceHigh5xxRate` live pode ter expressão legada — **Caminho A (natural)** ou **Caminho B (controlado)**. Entrega externa depende de credenciais.

### 6.1 Incidente proposital (T2 watch, T1 ação)
```bash
# T2 — observar
kubectl -n feature-flags get pods -l app=auth-service -w
# T1 — falha proposital/reversível
kubectl -n feature-flags scale deploy/auth-service --replicas=0
kubectl -n feature-flags get deploy/pods -l app=auth-service
```
**Falar:** “Para demonstrar detecção e resposta, provoco uma **falha controlada e reversível**. No *watch* (T2) observo pods do `auth-service`; em (T1) escalo o deployment para **zero réplicas**. O `auth-service` valida identidade; escalá-lo a zero simula indisponibilidade real. No *watch* os pods terminam e somem — incidente proposital claro, observável e reversível.”

### 6.2 Alerta em Firing — detecção e roteamento (A4, A2, T1)
```bash
kubectl -n observability get prometheusrules
kubectl -n observability describe prometheusrule auth-service-5xx-alert | sed -n '1,160p'
kubectl -n observability get alertmanagerconfig alertmanager-selfhealing -o yaml | sed -n '1,160p'
```
**Clique (A4):** Alerting → Alert rules → **`AuthServiceHigh5xxRate`** (ou regra de demo): estado *Pending/Firing*, expressão, `for`, labels `severity=critical, service=auth-service`.

**Falar (Caminho A/natural):** “Com o incidente, mostro detecção e tratamento. Em *Alerting* acompanho **`AuthServiceHigh5xxRate`**, avaliada continuamente pelo **Prometheus**; mantida verdadeira pelo `for`, passa a **Firing** (problema confirmado). O **Alertmanager** orquestra a resposta: o `AlertmanagerConfig` mostra alertas críticos agrupados (ex.: por alerta/serviço) e roteados para **webhook interno** `http://self-healing-webhook.self-healing.svc.cluster.local:8080/webhook`, e integrações externas **PagerDuty** e **Slack** (`#togglemaster-alerts`). Separação clara: detecção por métricas e roteamento notificando pessoas e automação ao mesmo tempo.”

**Caminho B (controlado — se não Firing a tempo por drift de métrica):** aplicar regra temporária, mostrar **`DemoAlwaysFiring`** Firing em A4 (`service=auth-service`), **remover após demo**.
```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: demo-firing-test
  namespace: observability
  labels:
    release: kube-prometheus-stack
spec:
  groups:
  - name: demo-test
    rules:
    - alert: DemoAlwaysFiring
      expr: vector(1)
      for: 15s
      labels:
        severity: critical
        service: auth-service
      annotations:
        summary: "Alerta de demonstração (temporário)"
        description: "Evidencia Firing/roteamento; remover após demo."
YAML
# após demonstrar:
# kubectl -n observability delete prometheusrule demo-firing-test
```
**Falar (Caminho B):** “Para garantir **Firing** e a cadeia de resposta no tempo da apresentação — considerando diferença conhecida entre expressão versionada e regra live — evidencio de forma controlada: aplico `PrometheusRule` temporária **`DemoAlwaysFiring`** (`expr: vector(1)`, `for:15s`) com labels `severity=critical, service=auth-service`, mostrando transição para *Firing* e roteamento no Alertmanager. Concluída a prova, removo a regra. O incidente real (indisponibilidade do `auth-service`) permanece como gatilho operacional analisado.”

### 6.3 Incidente no PagerDuty e notificação no Slack (A8, A9)
**Clique:** **A8** PagerDuty — incidente recente (título, severidade, horário, serviço). **A9** Slack `#togglemaster-alerts` (mensagem `[CRÍTICO]`/`auth-service`). **Alternativa (se entrega externa falhar):** A4 + `AlertmanagerConfig` (T1) com *receivers* + logs **T3** do webhook recebendo/processando.

**Falar (entrega ok):** “Com o alerta *Firing*, no **PagerDuty** vejo o incidente aberto (alerta, severidade, momento, serviço impactado), formalizando resposta com rastreabilidade. Em paralelo, no **Slack** `#togglemaster-alerts` chega a notificação, dando visibilidade imediata. Integração: Prometheus identifica, Alertmanager roteia e *receivers* entregam para gestão de incidentes e canal de mensagens.”

**Falar (contingência):** “Se a entrega externa não aparecer por credencial/webhook/canal (dependências fora do cluster), ainda comprovo o **roteamento interno**: `AlertmanagerConfig` mostra destinos (webhook, PagerDuty, Slack) e os logs do `self-healing-webhook` mostram recebimento/processamento interno. Detecção e encaminhamento pelo Alertmanager funcionam; a variável externa seria a confirmação do provedor.”

### 6.4 Ação corretiva do Self-Healing — pod reiniciando (T3, T2, T1)
```bash
# T3 — evidência de acionamento
kubectl -n self-healing logs deploy/self-healing-webhook --tail=120

# T1 — correção/restauração (evidencia recuperação)
kubectl -n feature-flags scale deploy/auth-service --replicas=1
kubectl -n feature-flags rollout restart deployment/auth-service -n feature-flags
kubectl -n feature-flags rollout status deployment/auth-service
kubectl -n feature-flags get pods -l app=auth-service

# se Caminho B:
# kubectl -n observability delete prometheusrule demo-firing-test
```
**Evidência:** **T3** logs (alerta recebido/ação); **T2** *watch* `auth-service` **Terminating → ContainerCreating/Pending → Running**; **T1** `rollout status` **successfully rolled out** e novo pod **Running**.

**Falar:** “Agora a **ação corretiva automática**. O **Alertmanager** envia HTTP `POST /webhook` ao `self-healing-webhook` (`self-healing`, serviço interno). Nos logs (T3) vejo o alerta recebido e tratado.

O webhook valida que o serviço está permitido (`auth-service`) e chama a **API do Kubernetes** para `rollout restart` do deployment `auth-service` em `feature-flags`, recriando pods de forma controlada pelo mecanismo de rollout. A ação é autorizada pela **ServiceAccount** e **RBAC** de menor privilégio naquele namespace.

Prova em tempo real: no *watch*, o pod antigo encerra e um novo surge (*ContainerCreating* → **Running**); `rollout status` confirma sucesso. Ciclo completo: **incidente proposital** → **Prometheus detecta** e alerta em **Firing** → **Alertmanager roteia** para canais e automação → **Self-Healing executa correção**, com **pod reiniciado e serviço recuperado**.”

---

## 7) Fechamento (30 s) — mapeamento à regra

**Tela:** síntese (ArgoCD apps, Grafana dashboard, Datadog Service Map) ou terminal com `auth-service` **Running** recuperado.

**Falar:** “Para concluir, demonstrei com evidências no repositório e no ambiente em operação todos os requisitos: no repositório, **IaC e GitOps**, configuração da observabilidade com **OpenTelemetry Collector**, **instrumentação OpenTelemetry** nos cinco serviços e **automação de Self-Healing** com RBAC; no cluster, **EKS provisionado por IaC** e gestão por **ArgoCD** com stack ativa; **métricas** no Grafana em **dashboard customizado** alimentado por *spanmetrics*, **logs centralizados no Loki** e **roteamento pelo OTel Collector**; no Datadog, **APM** com **Service Map** e **trace distribuído detalhado** via requisição de teste; e um **incidente proposital** que levou o alerta a **Firing**, gerou notificação/acionamento configurado e foi corrigido pelo **Self-Healing**, com **pod reiniciando e serviço recuperado**. Encerro a demonstração do ToggleMaster.”

---

## 8) Checklist rápido de contingência

| Situação | O que fazer | Evidência alternativa |
|---|---|---|
| **UI/NodePort inacessível** | outro IP de nó (`34.229.45.189/18.206.239.193/54.211.248.7/3.224.114.200`) ou `port-forward` (Grafana `3000:80`, ArgoCD `8443:443`, eval `18004:8004`) | `kubectl` comprovando serviços/pods |
| **Datadog vazio** | US5, `env:demo`, **Past 1h**, gerar tráfego | A7 (traces) / Services `env:demo` |
| **Loki ausente no Explore** | hard refresh/login; datasource **Loki** `uid=loki` → `http://loki.observability.svc.cluster.local:3100` | `kubectl -n observability get svc loki` + pods |
| **Alert rules “dentro” do dashboard** | mostrar em **Grafana Alerting** (`/alerting/list`) e `PrometheusRule/AlertmanagerConfig` (JSON do dashboard não embute rules) | `kubectl -n observability get prometheusrules,alertmanagerconfig` |
| **Argo `self-healing-webhook` Degraded/Progressing** | webhook **1/1 Running**; *health* por RS antigo/tag — **não sync** collector/self-healing na demo | `kubectl -n self-healing get deploy,pods,rs`; `/healthz` |
| **Alerta não entra em Firing** | evidenciar objetos e usar **Caminho B** (`DemoAlwaysFiring`, remover ao final) + prova real do pod/self-healing | A4 + logs webhook + *watch* pod |
| **PagerDuty/Slack sem entrega** | depende de credenciais externas; comprovar roteamento/acionamento interno | `AlertmanagerConfig alertmanager-selfhealing` + logs webhook (T3) |
| **Regra de ouro** | **não sincronizar** `opentelemetry-collector` nem drifts controlados | — |
