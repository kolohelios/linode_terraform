terraform {
    required_providers {
        linode = {
            source  = "linode/linode"
            version = "1.26.0"
        }
        kubernetes = {
            source  = "hashicorp/kubernetes"
            version = ">= 2.0.0"
        }
    }
}

resource "linode_lke_cluster" "kolohelios_cluster" {
    label       = "kolohelios"
    k8s_version = "1.24"
    region      = "us-west"
    tags        = ["prod"]

    pool {
        type  = "g6-standard-1"
        count = 3

        autoscaler {
            min = 3
            max = 6
        }
    }

    # Prevent the count field from overriding autoscaler-created nodes
    lifecycle {
    ignore_changes = [
        pool.0.count
    ]
    }
}

resource "local_file" "kube_config" {
    content  = base64decode(linode_lke_cluster.kolohelios_cluster.kubeconfig)
    filename = "kubeconfig"
}

provider "kubernetes" {
    config_path = "kubeconfig"
}
