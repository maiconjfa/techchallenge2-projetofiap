# Guia da cena: GitOps + ArgoCD (2 passos obrigatórios do projeto)

Objetivo da cena — provar, **ao vivo e com os 5 microsserviços**, os dois requisitos:

1. **GitOps**: "Mostre o pipeline atualizando a tag da imagem no repositório de GitOps."
2. **ArgoCD**: "Mostre o ArgoCD detectando a mudança e sincronizando a nova versão no cluster automaticamente."

O gatilho dispara o **CI dos 5 serviços de uma vez**, então as **5 tags** são bumpadas e as
**5 Applications** sincronizam — o sync fica visível na grade inteira do ArgoCD.

Pré-condição: **ArgoCD já sincronizado** (5 Applications `Synced/Healthy`) e pipeline verde.

> Por que não usar `provocar-lint` como gatilho? O `provocar-lint` é **vermelho de propósito** e
> **não** chega ao job `update-gitops` — logo não gera bump. O sync exige um run **VERDE**, que é
> exatamente o que `provocar-gitops.sh` produz.

---

## Passo 0 — Confirmar que o ArgoCD está já sincronizado (1 min)

```bash
kubectl get applications -n argocd
kubectl get pods -n feature-flags
```

Na UI do ArgoCD (`kubectl port-forward svc/argocd-server -n argocd 8080:443`, admin + senha do
`argocd-initial-admin-secret`), mostrar a grade das **5 Applications `Synced/Healthy`**.

> **Para falar:** "Este é o estado real do cluster: ArgoCD e Git concordam, as **5 aplicações estão
> `Synced` e `Healthy`**. O Git é a fonte da verdade. Agora vou provar o ciclo por inteiro, ao vivo:
> um único push dispara os **5 pipelines**, cada um atualiza a tag do seu serviço no repositório
> GitOps, e o ArgoCD sincroniza as cinco — **sem um único clique meu**."

---

## Passo 1 — GitOps: pipelines atualizando as 5 tags no repositório (3–5 min)

### 1.1 Sincronizar a main (o bot do CI comita bumps; segurança antes de provocar)

```bash
git pull --rebase origin main
```

### 1.2 Disparar o push verde (mudança benigna: um comentário em cada serviço)

```bash
bash docs/scripts/provocar-gitops.sh
```

O script adiciona **uma linha de comentário** no arquivo de entrada de cada serviço
(`auth-service/main.go`, `evaluation-service/main.go`, `analytics-service/app.py`,
`flag-service/app.py`, `targeting-service/app.py`) — passa em build, lint, SAST e SCA —,
commita `demo(gitops): ...` e faz push. **O filtro de caminho de cada workflow casa com o
diretório do seu serviço → os 5 pipelines disparam.**

### 1.3 Acompanhar os runs no GitHub Actions

Abrir **Actions** (`https://github.com/maiconjfa/techchallenge2-projetofiap/actions`) — serão
**5 runs** (auth, analytics, evaluation, flag, targeting), todos verdes:

```
Build & Unit Test (<servico>)                     -> verde
Lint (<servico>)                                  -> verde
Security Scan - SAST & SCA (<servico>)            -> verde
Docker Build & Container Scan & Push (<servico>)  -> verde (imagem nova no ECR)
Update GitOps - nova tag (<servico>)              -> comita o bump  <- FOCO DA CENA
```

Os jobs `Update GitOps` são **serializados** (concurrency `gitops-update`), então os bumps
entram um a um. Quando (pelo menos) o do auth terminar:

### 1.4 Mostrar os bumps no repositório GitOps

```bash
git fetch origin main && git show origin/main:gitops/apps/auth-service/kustomization.yaml
```

Mostrar conf `images[].newTag` apontando para a imagem nova (`v1.0.0-<sha7>`). Para mostrar os
bumps dos 5 serviços de uma vez — os commits do bot:

```bash
git log origin/main --oneline -6 -- gitops/apps/
```

Deve aparecer uma sequência como `ci(auth-service): bump image to v1.0.0-<sha>`,
`ci(analytics-service): bump ...`, `ci(evaluation-service): ...`, etc. (escrita pelo
`github-actions[bot]`).

> **Para falar:** "Do push às imagens no ECR, cada pipeline passou por **build, lint, security
> (SAST + SCA bloqueando CRITICAL/HIGH)** e push da imagem. No último job, cada pipeline escreve
> sozinho a **tag do seu serviço** no repositório **GitOps** — `gitops/apps/<servico>/kustomization.yaml`.
> O CI **não aplica nada no cluster**: ele só atualiza **uma linha do YAML** para apontar a
> imagem nova. Quem age no cluster é o próximo passo."

---

## Passo 2 — ArgoCD: detecção e sync automático dos 5 serviços (1–2 min)

Para **ver o flip acontecendo ao vivo**, abra a grade do ArgoCD e, em outro terminal:

```bash
kubectl get applications -n argocd -w
```

Conforme cada bump chega, a Application correspondente muda de `Synced` para **`OutOfSync`** e
volta para **`Synced/Healthy`** sozinha — o `syncPolicy.automated` com `prune + selfHeal`
(`gitops/argocd/applications/auth-service.yaml:26-29`). As **5** fazem isso em sequência.

Confirmar a convergência (pode rodar para todos os serviços ou só o auth como exemplo):

```bash
kubectl rollout status deployment/auth-service -n feature-flags --timeout=180s
kubectl get pods -n feature-flags
```

`kubectl get pods` deve mostrar **pods novos em todos os serviços** (ReplicaSets recentes) —
o rolling update aconteceu nas 5.

> **Para falar:** "O GitOps mudou **uma linha em 5 YAMLs**. O ArgoCD, que vigia o repositório sem
> parar, detectou a divergência entre o desejado (Git) e o real (cluster) servidor por servidor,
> marcou `OutOfSync` e **sincronizou automaticamente** — estratégia `automated` com `prune` e
> `selfHeal`. O `kubectl` aqui é só para confirmar: as cinco aplicações rolou o pod antigo para o
> pod novo com a imagem recém-buildada."

---

## Passo 3 — Fechar a cena (deixar tudo verde e limpo)

```bash
bash docs/scripts/reverter-gitops.sh
```

Reverte o commit `demo(gitops)` (os 5 arquivos) e faz um novo push verde → os 5 pipelines rodam
de novo → 5 novas imagens → 5 novos bumps → ArgoCD sincroniza a versão final. Exibir os runs
verdes e as 5 Applications `Synced/Healthy`. O repositório fica **sem marcador de demonstração**.

> **Para falar (encerramento):** "Resumo do que acabamos de ver: **GitOps no CI** — o pipeline
> entrega a imagem e **escreve a tag no repositório**; **ArgoCD no CD** — detecta a mudança e
> **converge o cluster sozinho**. Estado real = estado desejado, e `selfHeal`/`prune` garantem
> que ele nunca diverge."

---

## Troubleshooting da cena

| Sintoma | Causa | Solução |
|---|---|---|
| `error: unable to read commit message from '.git/MERGE_MSG'` (WSL/DrvFS) ao rodar `reverter-gitops.sh` | O revert aplicou e estagiou, mas o git não relê `MERGE_MSG` | Commit direto e push: `git commit -F .git/MERGE_MSG` (ou `-m "Revert \"demo(gitops): ...\""`) e `git push origin main` |
| `ERRO: main local nao sincronizada` ao rodar `provocar-gitops.sh` | O bot do CI comitou bumps e origin avançou | `git pull --rebase origin main` e repetir |
| `ja existe demo(gitops) pendente` ao provocar | Uma cena anterior não foi fechada | `bash docs/scripts/reverter-gitops.sh` antes de provocar de novo |
| Algum run ficou vermelho no `provocar-gitops.sh` | Algum gate não passou (não deveria acontecer) | Reverter: `bash docs/scripts/reverter-gitops.sh` e investigar o job vermelho |
| `rollout status` não converge / app some da grade | O `update-gitops` do serviço ainda não commitou | Aguardar o run terminar (5º job) e conferir `gitops/apps/<servico>/kustomization.yaml`; o fluxo é verde → bump → sync |
| ArgoCD não sincroniza | Repo/targetRevision ou polling ainda não rodou | ArgoCD verifica o repo a cada ~3 min; aguardar ou `argocd app sync <servico>` só como diagnóstico |