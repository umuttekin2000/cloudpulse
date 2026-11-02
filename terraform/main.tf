# ─────────────────────────────────────────────────────────────────────────────
# CloudPulse: Kubernetes "bootstrap" infrastructure.
# Terraform manages sensitive data (secrets) and configuration here:
# * Namespace
# * cloudpulse-config   (ConfigMap, non-sensitive settings)
# * cloudpulse-secrets  (Secret, values come from sensitive = true variables)
# * ghcr-pull-secret    (Optional, to pull private images from GHCR)
# Application workloads (MySQL, Redis, MinIO, Laravel) are deployed via manifests
# under k8s/:   make deploy CONFIG_SOURCE=terraform
# CAUTION: The Terraform state file contains SECRETS IN PLAIN TEXT. In a real environment,
# use an encrypted remote backend (S3 + KMS, GCS, Terraform Cloud, etc.);
# never commit the local terraform.tfstate file (it is in .gitignore).
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

locals {
  # Must be IDENTICAL to the names that the manifests under k8s/ bind with envFrom.
  config_map_name        = "cloudpulse-config"
  secret_name            = "cloudpulse-secrets"
  image_pull_secret_name = "ghcr-pull-secret"

  labels = {
    "app.kubernetes.io/part-of"    = "cloudpulse"
    "app.kubernetes.io/managed-by" = "terraform"
  }
}

resource "kubernetes_namespace_v1" "cloudpulse" {
  metadata {
    name   = var.namespace
    labels = local.labels
  }
}

resource "kubernetes_config_map_v1" "app" {
  metadata {
    name      = local.config_map_name
    namespace = kubernetes_namespace_v1.cloudpulse.metadata[0].name
    labels    = local.labels
  }

  data = var.app_config
}

resource "kubernetes_secret_v1" "app" {
  metadata {
    name      = local.secret_name
    namespace = kubernetes_namespace_v1.cloudpulse.metadata[0].name
    labels    = local.labels
  }

  type = "Opaque"

  # The provider converts these values to base64; they are masked in the plan output.
  data = {
    APP_KEY                 = var.app_key
    DB_ROOT_PASSWORD        = var.db_root_password
    DB_PASSWORD             = var.db_password
    DB_REPLICATION_PASSWORD = var.db_replication_password
    REDIS_PASSWORD          = var.redis_password
    MINIO_ROOT_USER         = var.minio_root_user
    MINIO_ROOT_PASSWORD     = var.minio_root_password
    AWS_ACCESS_KEY_ID       = var.minio_root_user
    AWS_SECRET_ACCESS_KEY   = var.minio_root_password
  }
}

# Image pull secret to pull GHCR private packages (same PAT as GHCR_PAT).
resource "kubernetes_secret_v1" "ghcr_pull" {
  count = var.create_image_pull_secret ? 1 : 0

  metadata {
    name      = local.image_pull_secret_name
    namespace = kubernetes_namespace_v1.cloudpulse.metadata[0].name
    labels    = local.labels
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        (var.registry_server) = {
          username = var.ghcr_username
          password = var.ghcr_pat
          auth     = base64encode("${var.ghcr_username}:${var.ghcr_pat}")
        }
      }
    })
  }
}
