terraform {
    required_providers {
        linode = {
            source  = "linode/linode"
            version = "1.26.0"
        }
    }
}

resource "linode_lke_cluster" "kolohelios" {
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
