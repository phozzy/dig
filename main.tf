data "google_client_config" "default" {
  provider = google-beta
}
provider "google-beta" {
  credentials = file("key.json")
  project     = "dinsurance"
  region      = "us-central1"
  version     = "~> 3.29.0"
}
provider "kubernetes" {
  load_config_file       = false
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    load_config_file       = false
    host                   = "https://${google_container_cluster.primary.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth.0.cluster_ca_certificate)
  }
}
resource "google_container_cluster" "primary" {
  provider                 = google-beta
  name                     = "dinsurance"
  location                 = "us-central1"
  remove_default_node_pool = true
  initial_node_count       = 1
  release_channel {
    channel = "RAPID"
  }
}
resource "google_container_node_pool" "primary_preemptible_nodes" {
  provider           = google-beta
  name               = "dinsurance-node-pool"
  location           = "us-central1"
  cluster            = google_container_cluster.primary.name
  initial_node_count = 1
  autoscaling {
    min_node_count = 1
    max_node_count = 9
  }
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 1
  }
  node_config {
    preemptible  = true
    machine_type = "n1-standard-1"
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}
resource "kubernetes_namespace" "monitoring" {
  depends_on = [
    google_container_node_pool.primary_preemptible_nodes,
  ]
  metadata {
    annotations = {
      name = "monitoring"
    }
    labels = {
      workload = "monitoring"
    }
    name = "monitoring"
  }
}
resource "google_compute_address" "nginx-ingress-ip" {
  depends_on = [
    google_container_node_pool.primary_preemptible_nodes,
  ]
  name     = "nginx-ingress-controller"
  provider = google-beta
}
resource "helm_release" "prometheus-operator" {
  depends_on = [
    google_container_node_pool.primary_preemptible_nodes,
  ]
  repository = "https://kubernetes-charts.storage.googleapis.com"
  name  = "prometheus-operator"
  chart = "prometheus-operator"
  namespace = "${kubernetes_namespace.monitoring.metadata.0.name}"

  timeout = 1200

  values = [
    "${file("./helm/prometheus-operator/values.yaml")}"
  ]
}
resource "helm_release" "nginx-ingress" {
  depends_on = [
    helm_release.prometheus-operator,
  ]
  name       = "nginx-ingress-dinsurance"
  repository = "https://kubernetes-charts.storage.googleapis.com"
  chart      = "nginx-ingress"

  set {
    name = "controller.service.loadBalancerIP"
    value = google_compute_address.nginx-ingress-ip.address
  }

  values = [
    "${file("./helm/ingress/values.yaml")}"
  ]
}
resource "helm_release" "hello-app" {
  depends_on = [
    helm_release.nginx-ingress,
  ]
  name = "hello-app"
  chart = "./helm/hello-app"
}
