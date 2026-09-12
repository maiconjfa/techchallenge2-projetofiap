###############################################################################
# Aplica os manifests Kustomize do ArgoCD no cluster EKS.
#
# O provider kbst/kustomization faz server-side apply com deteccao de drift.
# ids_prio divide os recursos em grupos de precedencia:
#   [0] namespaces e CRDs -> [1] recursos cluster-scoped -> [2] namespaced
###############################################################################

terraform {
  required_providers {
    kustomization = {
      source  = "kbst/kustomization"
      version = "~> 0.9"
    }
  }
}

data "kustomization_build" "argocd" {
  path = "${path.module}/manifests"
}

resource "kustomization_resource" "p0" {
  for_each = try(toset(data.kustomization_build.argocd.ids_prio[0]), [])

  manifest = data.kustomization_build.argocd.manifests[each.key]
}

resource "kustomization_resource" "p1" {
  depends_on = [kustomization_resource.p0]

  for_each = try(toset(data.kustomization_build.argocd.ids_prio[1]), [])

  manifest = data.kustomization_build.argocd.manifests[each.key]
}

resource "kustomization_resource" "p2" {
  depends_on = [kustomization_resource.p1]

  for_each = try(toset(data.kustomization_build.argocd.ids_prio[2]), [])

  manifest = data.kustomization_build.argocd.manifests[each.key]
}
