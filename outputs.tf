output "namespace" {
  description = "Namespace the service runs in."
  value       = kubernetes_namespace.halden.metadata[0].name
}

output "service_name" {
  description = "In-cluster DNS name halden-identity resolves."
  value       = "${kubernetes_service.threat_detection.metadata[0].name}.${kubernetes_namespace.halden.metadata[0].name}.svc.cluster.local"
}

output "service_external_ip" {
  description = "Public address assigned to the load balancer."
  value       = try(kubernetes_service.threat_detection.status[0].load_balancer[0].ingress[0].ip, null)
}

output "postgres_fqdn" {
  description = "Private FQDN of the detection database."
  value       = azurerm_postgresql_flexible_server.detection.fqdn
}

output "deployed_image_tag" {
  description = "Image tag currently deployed."
  value       = var.image_tag
}
