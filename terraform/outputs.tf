output "namespace" {
  description = "The created namespace."
  value       = kubernetes_namespace_v1.cloudpulse.metadata[0].name
}

output "config_map_name" {
  description = "The ConfigMap that the application reads from with envFrom."
  value       = kubernetes_config_map_v1.app.metadata[0].name
}

output "secret_name" {
  description = "The Secret that the application reads from with envFrom."
  value       = kubernetes_secret_v1.app.metadata[0].name
}

output "image_pull_secret_name" {
  description = "GHCR image pull secret (if created)."
  value       = var.create_image_pull_secret ? kubernetes_secret_v1.ghcr_pull[0].metadata[0].name : null
}

output "next_step" {
  description = "The next command to run."
  value       = "make deploy CONFIG_SOURCE=terraform"
}
