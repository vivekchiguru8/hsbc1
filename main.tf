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

# 3. Deployment - nginx with 2 replicas in vivek namespace
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
}

# 4. HPA for nginx deployment in vivek namespace
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
          type                 = "Utilization"
          average_utilization = 70
        }
      }
    }
  }
}

output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "deployment_name" {
  value = kubernetes_deployment.nginx.metadata[0].name
}