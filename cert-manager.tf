variable "cert_manager_chart_name" {
  type        = string
  description = "Cert Manager Helm name"
}
variable "cert_manager_chart_repo" {
  type        = string
  description = "Cert Manager Helm repository name"
}
variable "cert_manager_chart_version" {
  type        = string
  description = "Cert Manager Helm version"
}

resource "kubernetes_namespace" "cert_manager_namespace" {
  depends_on = [time_sleep.wait_210_seconds]

  metadata {
    annotations = {
      name = "cert-manager"
    }
    name = "cert-manager"
  }
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  namespace  = kubernetes_namespace.cert_manager_namespace.id
  chart      = var.cert_manager_chart_name
  repository = var.cert_manager_chart_repo
  version    = var.cert_manager_chart_version

  set {
    name  = "installCRDs"
    value = "true"
  }
}
