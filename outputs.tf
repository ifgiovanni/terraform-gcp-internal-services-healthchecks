
output "namespaces" {
  value = google_service_directory_namespace.ns
}

output "services" {
  value = google_service_directory_service.svc
}

output "endpoints" {
  value = google_service_directory_endpoint.ep
}

output "uptime_checks" {
  value = google_monitoring_uptime_check_config.sd
}

output "alert_policies" {
  value = google_monitoring_alert_policy.uptime
}
