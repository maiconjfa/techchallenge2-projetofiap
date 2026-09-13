# Guia da cena: GitOps + ArgoCD (2 passos obrigatórios do projeto)

Objetivo da cena — provar, **ao vivo**, os dois requisitos:

1. **GitOps**: "Mostre o pipeline atualizando a tag da imagem no repositório de GitOps."
2. **ArgoCD**: "Mostre o ArgoCD detectando a mudança e sincronizando a nova versão no cluster automaticamente."

Pré-condição: **ArgoCD já sincronizado** (5 Applications `Synced/Healthy`) e pipeline verde.
É exatamente o estado em que deixamos o projeto ao fim da Etapa 1.

> Este guia existe porque o gatilho precisa gerar um run **VERDE**. Um `provocar-lint`
> (vermelho de propósito) **não** produz o bump — por isso usamos o gatilho benigno
> `provocar-gitops.sh`.

---

## Passo 0 — Confirmar que o ArgoCD está já sincronizado (1 min)

```bash
kubectl get applications -n argocd
kubectl get pods -n feature-flags
```

Na UI do ArgoCD (`kubectl port-forward svc/argocd-server -n argocd 8080:443`, admin + senha do
`argocd-initial-admin-secret`), mostrar a grade das **5 Applications `Synced/Healthy`**.

> **Para falar:** "Este é o estado real do cluster: o ArgoCD e o Git concordam, as 5 aplicações
> estão **Synced e Healthy**. O Git é a fonte da verdade. Agora vou provar o ciclo por inteiro
> ao vivo: o pipeline vai atualizar a tag da imagem no repositório GitOps, e o ArgoCD vai
> sincronizar essa nova versão — **sem nenhum clique meu**."

---

## Passo 1 — GitOps: pipeline atualizando a tag no repositório (2–4 min)

### 1.1 Sincronizar a main (o bot do CI comita bumps; segurança antes de provocar)

```bash
git pull --rebase origin main
```

### 1.2 Disparar o push verde (uma mudança benigna: versão do app no log)

```bash
bash docs/scripts/provocar-gitops.sh
```

O script edita `auth-service/main.go` (adiciona `const appVersion` **usada** no log — passa em
build, lint, gosec e Trivy), commita `demo(gitops): ...` e faz push.

### 1.3 Acompanhar o run no GitHub Actions

Abrir **Actions → run do auth CI** (link impresso pelo script ou
`https://github.com/maiconjfa/techchallenge2-projetofiap/actions`).
Acompanhar os jobs em sequência:

```
Build & Unit Test (auth-service)          -> verde
Lint (auth-service)                       -> verde
Security Scan - SAST & SCA (auth-service) -> verde
Docker Build & Container Scan & Push      -> verde (imagem nova no ECR)
Update GitOps - nova tag (auth-service)   -> comita o bump  <- FOCO DA CENA
```

Quando o job **`Update GitOps - nova tag (auth-service)`** terminar (5º job):

### 1.4 Mostrar o bump no repositório GitOps

Abrir o arquivo `gitops/apps/auth-service/kustomization.yaml`:

```bash
git fetch origin main && git show origin/main:gitops/apps/auth-service/kustomization.yaml
```

Conferir a linha `images[].newTag` — agora aponta para a nova imagem
(`v1.0.0-<sha7 do commit>`). Pode-se mostrar também o commit pelo GitHub:

```bash
git log origin/main --oneline -3 -- gitops/apps/auth-service
```

Deve aparecer: `ci(auth-service): bump image to v1.0.0-<sha7>` (escrito pelo `github-actions[bot]`).

> **Para falar:** "Do push à imagem no ECR, o pipeline passou por **build, lint, security scan
> (SAST + SCA bloqueando CRITICAL/HIGH)** e push da imagem. No último job, ele escreve sozinho
> a nova tag no repositório **GitOps** — `gitops/apps/auth-service/kustomization.yaml`. O CI
> **não aplica nada no cluster**; ele apenas atualiza **uma linha do YAML** apontando para a
> imagem nova. Quem age no cluster é o próximo passo."
>

---

## Passo 2 — ArgoCD: detecção e sync automático (1–2 min)

Voltar para a UI do ArgoCD e clicar na Application `auth-service`. Ela deve **piscar `OutOfSync`
e voltar a `Synced/Healthy`** sozinha — sinal do `syncPolicy.automated` com `prune + selfHeal`
(`gitops/argocd/applications/auth-service.yaml:26-29`).

Confirmar a convergência no terminal:

```bash
kubectl rollout status deployment/auth-service -n feature-flags --timeout=180s
kubectl get pods -n feature-flags
```

O `rollout status` termina com sucesso e `kubectl get pods` mostra o **pod novo** (rolling update)
no lugar do antigo.

> **Para falar:** "O GitOps mudou **uma linha num YAML**. O ArgoCD, que vigia o repositório sem
> parar, detectou a divergência entre o desejado (Git) e o real (cluster), marcou **OutOfSync** e
> sincronizou **automaticamente** — estratégia `automated` com `prune` e `selfHeal`. O `kubectl`
> aqui é só para confirmar: o pod antigo rolou para o pod novo com a imagem recém-buildada."
>

---

## Passo 3 — Fechar a cena (deixar tudo verde e limpo)

```bash
bash docs/scripts/reverter-gitops.sh
```

Reverte o commit `demo(gitops)` e faz um novo push verde → nova imagem → novo bump → ArgoCD
sincroniza a versão final. Exibir o run verde no Actions e as 5 Applications `Synced/Healthy`.
O repositório fica **sem marcador de demonstração** para a próxima cena.

> **Para falar (encerramento):** "Resumo do que acabamos de ver: **fluxo GitOps no CI** — o
> pipeline entrega a imagem e **escreve a tag no repositório**; **ArgoCD no CD** — detecta a
> mudança e **converge o cluster sozinho**. Estado real = estado desejado."

---

## Troubleshooting da cena

| Sintoma | Causa | Solução |
|---|---|---|
| `error: unable to read commit message from '.git/MERGE_MSG'` (WSL/DrvFS) ao rodar `reverter-gitops.sh` | O revert aplicou e estagiou, mas o git não relê `MERGE_MSG` | Commit direto e push: `git commit -F .git/MERGE_MSG` (ou `-m "Revert \"demo(gitops): ...\""`) e `git push origin main` |
| `ERRO: main local nao sincronizada` ao rodar `provocar-gitops.sh` | O bot do CI comitou o bump e origin avançou | `git pull --rebase origin main` e repetir |
| Run ficou vermelho no `provocar-gitops.sh` | Algum gate não passou (não deveria acontecer) | Reverter: `bash docs/scripts/reverter-gitops.sh` e investigar o job vermelho |
| `rollout status` não converge | O `update-gitops` ainda não commitou o bump | Aguardar o run terminar (job 5) e conferir `gitops/apps/auth-service/kustomization.yaml`; o processo é verde → bump → sync |
| ArgoCD não sincroniza | Repo/targetRevision ou credencial do ArgoCD | Conferir a Application `auth-service.yaml` (repo público não exige token); `argocd app sync auth-service` manual só como diagnóstico |