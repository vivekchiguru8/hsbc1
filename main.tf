terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "google" {
  project = "project-10094705-9153-43d5-bb8"
  region  = "asia-south1"
}

# 1. GKE Cluster Only
resource "google_container_cluster" "primary" {
  name                = "my-gke-cluster"
  location            = "asia-south1-a"
  initial_node_count  = 2
  deletion_protection = false

  node_config {
    machine_type    = "e2-medium"
    disk_size_gb    = 30
    service_account = "645491051550-compute@developer.gserviceaccount.com"
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  cluster_autoscaling {
    enabled = true

    resource_limits {
      resource_type = "cpu"
      minimum       = 0
      maximum       = 8
    }

    resource_limits {
      resource_type = "memory"
      minimum       = 0
      maximum       = 32
    }
  }

  vertical_pod_autoscaling {
    enabled = true
  }
}

# Get cluster details for kubernetes provider
data "google_container_cluster" "primary" {
  name     = google_container_cluster.primary.name
  location = google_container_cluster.primary.location
}

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

# 2. New Namespace: vivek
resource "kubernetes_namespace" "vivek" {
  metadata {
    name = "vivek"
  }
}

# 3. First NGINX deployment with 2 replicas in vivek namespace
resource "kubernetes_deployment" "nginx" {
  metadata {
    name      = "nginx-deployment"
    namespace = kubernetes_namespace.vivek.metadata[0].name
    labels = {
      app = "nginx"
    }
  }
  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "nginx"
      }
    }
    template {
      metadata {
        labels = {
          app = "nginx"
        }
      }
      spec {
        container {
          name  = "nginx"
          image = "nginx:1.25"

          port {
            container_port = 80
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [spec[0].replicas]
  }
}

# 4. Second NGINX deployment with 2 replicas in vivek namespace
resource "kubernetes_deployment" "nginx_2" {
  metadata {
    name      = "nginx-deployment-2"
    namespace = kubernetes_namespace.vivek.metadata[0].name
    labels = {
      app = "nginx-2"
    }
  }
  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "nginx-2"
      }
    }
    template {
      metadata {
        labels = {
          app = "nginx-2"
        }
      }
      spec {
        container {
          name  = "nginx"
          image = "nginx:1.25"

          port {
            container_port = 80
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [spec[0].replicas]
  }
}

# 5. HPA for the first NGINX deployment in vivek namespace
resource "kubernetes_horizontal_pod_autoscaler_v2" "nginx_hpa" {
  metadata {
    name      = "nginx-hpa"
    namespace = kubernetes_namespace.vivek.metadata[0].name
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.nginx.metadata[0].name
    }

    min_replicas = 2
    max_replicas = 10

    metric {
      type = "Resource"

      resource {
        name = "cpu"

        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
  }
}

# 6. HPA for the second NGINX deployment in vivek namespace
resource "kubernetes_horizontal_pod_autoscaler_v2" "nginx_2_hpa" {
  metadata {
    name      = "nginx-hpa-2"
    namespace = kubernetes_namespace.vivek.metadata[0].name
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.nginx_2.metadata[0].name
    }

    min_replicas = 2
    max_replicas = 10

    metric {
      type = "Resource"

      resource {
        name = "cpu"

        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
  }
}

# 7. Dedicated identity for the management VM
resource "google_service_account" "gke_management" {
  account_id   = "gke-management"
  display_name = "GKE management server"
}

resource "google_project_iam_member" "gke_management_cluster_viewer" {
  project = "project-10094705-9153-43d5-bb8"
  role    = "roles/container.clusterViewer"
  member  = "serviceAccount:${google_service_account.gke_management.email}"
}

# Allow SSH only through IAP; the management VM has no external IP.
resource "google_compute_firewall" "gke_management_iap_ssh" {
  name     = "gke-management-iap-ssh"
  network  = "default"
  priority = 800

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["gke-management"]
}

resource "google_compute_firewall" "gke_management_deny_public_ssh" {
  name     = "gke-management-deny-public-ssh"
  network  = "default"
  priority = 900

  deny {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gke-management"]
}

resource "google_compute_subnetwork" "gke_management" {
  name          = "gke-management-subnet"
  ip_cidr_range = "172.16.0.0/24"
  region        = "asia-south1"
  network       = "default"
}

resource "google_compute_router" "gke_management" {
  name    = "gke-management-router"
  region  = "asia-south1"
  network = "default"
}

resource "google_compute_router_nat" "gke_management" {
  name                               = "gke-management-nat"
  router                             = google_compute_router.gke_management.name
  region                             = google_compute_router.gke_management.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.gke_management.self_link
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

resource "google_compute_instance" "gke_management" {
  name         = "gke-management"
  machine_type = "e2-medium"
  zone         = "asia-south1-a"
  tags         = ["gke-management"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-balanced"
    }
  }

  network_interface {
    network    = "default"
    subnetwork = google_compute_subnetwork.gke_management.self_link
  }

  service_account {
    email  = google_service_account.gke_management.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata = {
    startup-script = <<-SCRIPT
      #!/bin/bash
      set -euo pipefail

      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y ca-certificates curl
      install -d -m 0755 /usr/share/keyrings
      curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        -o /usr/share/keyrings/cloud.google.asc
      echo "deb [signed-by=/usr/share/keyrings/cloud.google.asc] https://packages.cloud.google.com/apt cloud-sdk main" \
        > /etc/apt/sources.list.d/google-cloud-sdk.list
      apt-get update
      apt-get install -y google-cloud-cli kubectl google-cloud-cli-gke-gcloud-auth-plugin
    SCRIPT
  }

  depends_on = [google_compute_router_nat.gke_management]
}

# Grant the VM service account Kubernetes administrator access to this cluster.
resource "kubernetes_cluster_role_binding" "gke_management_admin" {
  metadata {
    name = "gke-management-admin"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "User"
    name      = google_service_account.gke_management.unique_id
    api_group = "rbac.authorization.k8s.io"
  }
}

output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "deployment_name" {
  value = kubernetes_deployment.nginx.metadata[0].name
}

output "second_deployment_name" {
  value = kubernetes_deployment.nginx_2.metadata[0].name
}

output "management_server_name" {
  value = google_compute_instance.gke_management.name
}

output "management_server_ssh_command" {
  value = "gcloud compute ssh ${google_compute_instance.gke_management.name} --zone ${google_compute_instance.gke_management.zone} --project project-10094705-9153-43d5-bb8 --tunnel-through-iap"
}