terraform {
  required_version = "~> 1.3.6"
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 1.26.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "=3.9.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.16.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.7.1"
    }
  }
}

provider "cloudflare" {
  api_token = var.letsencrypt_cloudflare_api_token
}

provider "linode" {
  token = var.linode_token
}

resource "null_resource" "create_kubeconfig" {
  provisioner "local-exec" {
    command = "touch -c kubeconfig"
  }
}

resource "linode_lke_cluster" "kolohelios_cluster" {
  label       = "kolohelios"
  k8s_version = "1.24"
  region      = "us-west"
  tags        = ["prod"]

  pool {
    type  = "g6-standard-1"
    count = 1

    autoscaler {
      min = 1
      max = 6
    }
  }

  # Prevent the count field from overriding autoscaler-created nodes
  lifecycle {
    ignore_changes = [
      pool[0].count
    ]
  }
}

resource "local_file" "kube_config" {
  depends_on = [linode_lke_cluster.kolohelios_cluster]
  content    = base64decode(linode_lke_cluster.kolohelios_cluster.kubeconfig)
  filename   = "kubeconfig"
}

provider "kubernetes" {
  config_path = local_file.kube_config.filename
}

provider "kubectl" {
  config_path = local_file.kube_config.filename
}

provider "helm" {
  kubernetes {
    config_path = local_file.kube_config.filename
  }
}

resource "time_sleep" "wait_210_seconds" {
  depends_on = [linode_lke_cluster.kolohelios_cluster]

  create_duration = "210s"
}

resource "kubernetes_namespace" "traefik_namespace" {
  depends_on = [helm_release.cert_manager]
  metadata {
    annotations = {
      name = "traefik"
    }
    name = "traefik"
  }
}

resource "helm_release" "traefik" {
  depends_on = [kubernetes_namespace.traefik_namespace]
  name       = "traefik"
  namespace  = kubernetes_namespace.traefik_namespace.id
  chart      = var.traefik_chart_name
  repository = var.traefik_chart_repo
  version    = var.traefik_chart_version

  # Permanent HTTP to HTTPS redirect
  set {
    name  = "ports.web.redirectTo"
    value = "websecure"
  }

  set {
    name  = "providers.kubernetesIngress.publishedService.enabled"
    value = true
  }
}

resource "kubernetes_secret" "letsencrypt_cloudflare_api_token_secret" {
  depends_on = [time_sleep.wait_210_seconds]

  metadata {
    name      = "letsencrypt-cloudflare-api-token-secret"
    namespace = kubernetes_namespace.cert_manager_namespace.metadata.0.name
  }

  data = {
    "api-token" = var.letsencrypt_cloudflare_api_token
  }
}

# we're using kubectl_manifest instead of kubernetes_manifest because of the limitations in the latter which prevents idempotency
resource "kubectl_manifest" "letsencrypt_issuer_staging" {
  yaml_body = <<-EOF
      apiVersion: cert-manager.io/v1
      kind: ClusterIssuer
      metadata:
        name: letsencrypt-staging
      spec:
        acme:
          email: "${var.letsencrypt_email}"
          server: "https://acme-staging-v02.api.letsencrypt.org/directory"
          privateKeySecretRef:
            name: issuer-account-key-letsencrypt-staging
          solvers:
            - dns01:
                cloudflare:
                  apiTokenSecretRef:
                    name: "${kubernetes_secret.letsencrypt_cloudflare_api_token_secret.metadata.0.name}"
                    key: "${keys(kubernetes_secret.letsencrypt_cloudflare_api_token_secret.data).0}"
        EOF

  depends_on = [helm_release.cert_manager]
}

# we're using kubectl_manifest instead of kubernetes_manifest because of the limitations in the latter which prevents idempotency
resource "kubectl_manifest" "letsencrypt_issuer_production" {
  yaml_body = <<-EOF
      apiVersion: cert-manager.io/v1
      kind: ClusterIssuer
      metadata:
        name: letsencrypt-production
      spec:
        acme:
          email: "${var.letsencrypt_email}"
          server: https://acme-v02.api.letsencrypt.org/directory
          privateKeySecretRef:
            name: issuer-account-key-letsencrypt-production
          solvers:
            - dns01:
                cloudflare:
                  apiTokenSecretRef:
                    name: "${kubernetes_secret.letsencrypt_cloudflare_api_token_secret.metadata.0.name}"
                    key: "${keys(kubernetes_secret.letsencrypt_cloudflare_api_token_secret.data).0}"
        EOF

  depends_on = [helm_release.cert_manager]
}

data "kubernetes_service" "traefik" {
  depends_on = [helm_release.traefik]
  metadata {
    name      = helm_release.traefik.name
    namespace = helm_release.traefik.namespace
  }
}

# data "cloudflare_zone" "kolohelios_dev" {
#   name = "kolohelios.dev"
# }

# resource "cloudflare_record" "kolohelios_dev" {
#   zone_id = data.cloudflare_zone.kolohelios_dev.id
#   name    = "@"
#   type    = "A"
#   value   = data.kubernetes_service.traefik.status.0.load_balancer.0.ingress.0.ip
#   proxied = true
# }

resource "kubernetes_namespace" "hello" {
  depends_on = [helm_release.cert_manager]
  metadata {
    name = "hello"
  }
}


resource "kubernetes_deployment" "hello" {
  depends_on = [helm_release.cert_manager]
  metadata {
    name      = "hello-deploy"
    namespace = kubernetes_namespace.hello.metadata.0.name

    labels = {
      app = "hello"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "hello"
      }
    }

    template {
      metadata {
        labels = {
          app = "hello"
        }
      }

      spec {
        container {
          image = "nginxdemos/hello"
          name  = "hello"

          port {
            container_port = 80
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "hello" {
  depends_on = [helm_release.cert_manager]
  metadata {
    name      = "hello-svc"
    namespace = kubernetes_namespace.hello.metadata.0.name
    annotations = {
      "external-dns.alpha.kubernetes.io/hostname" = "kolohelios.dev"
      "external-dns.alpha.kubernetes.io/ttl"      = "120" # optional
    }
  }

  spec {
    selector = {
      app = kubernetes_deployment.hello.metadata.0.labels.app
    }

    port {
      port        = 80
      target_port = 80
    }
  }
}

resource "kubernetes_ingress_v1" "hello" {
  depends_on = [helm_release.cert_manager]
  metadata {
    name      = "hello-ing"
    namespace = kubernetes_namespace.hello.metadata.0.name
    annotations = {
      "cert-manager.io/cluster-issuer"            = "letsencrypt-production"
      "traefik.ingress.kubernetes.io/router.tls"  = "true"
      "external-dns.alpha.kubernetes.io/hostname" = "kolohelios.dev, www.kolohelios.dev"
      "external-dns.alpha.kubernetes.io/ttl"      = "120" # optional
    }
  }

  spec {
    rule {
      host = "kolohelios.dev"

      http {
        path {
          path = "/"

          backend {
            service {
              name = "hello-svc"

              port {
                number = 80
              }
            }
          }
        }
      }
    }

    rule {
      host = "www.kolohelios.dev"

      http {
        path {
          path = "/"

          backend {
            service {
              name = "hello-svc"

              port {
                number = 80
              }
            }
          }
        }
      }
    }

    tls {
      hosts       = ["*.kolohelios.dev"]
      secret_name = "hello-tls-secret"
    }
  }
}

resource "kubernetes_namespace" "external_dns" {
  depends_on = [helm_release.cert_manager]
  metadata {
    annotations = {
      name = "external-dns"
    }
    name = "external-dns"
  }
}

resource "helm_release" "external_dns" {
  depends_on = [helm_release.cert_manager]

  name       = "external-dns"
  namespace  = "external-dns"
  chart      = var.external_dns_chart_name
  repository = var.external_dns_chart_repo
  version    = var.external_dns_chart_version

  set {
    name  = "provider"
    value = "cloudflare"
  }
  set {
    name  = "cloudflare.apiToken"
    value = var.letsencrypt_cloudflare_api_token
  }

  set {
    name  = "cloudflare.proxied"
    value = true
  }

  set {
    name  = "publishServices"
    value = true
  }

  set {
    name  = "source"
    value = "ingress"
  }

  set {
    name  = "source"
    value = "service"
  }
}
