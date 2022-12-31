variable "traefik_chart_name" {
  type        = string
  description = "Traefik Ingress Gateway Helm chart name."
}

variable "traefik_chart_repo" {
  type        = string
  description = "Traefik Ingress Gateway Helm repository name."
}

variable "traefik_chart_version" {
  type        = string
  description = "Traefik Ingress Gateway Helm repository version."
}
