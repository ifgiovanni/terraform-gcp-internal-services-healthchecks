terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

# ─────────────────────────────────────────────────────────────
# 1. Namespaces
# ─────────────────────────────────────────────────────────────
resource "google_service_directory_namespace" "ns" {
  for_each = local.namespaces

  project      = var.project
  location     = var.location
  namespace_id = each.key
}

# ─────────────────────────────────────────────────────────────
# 2. Services
# ─────────────────────────────────────────────────────────────
locals {
  namespaces = {
    for ns_name in distinct([for s in var.services_flat : s.namespace]) :
    ns_name => {
      services = {
        for svc_name in distinct([
          for s in var.services_flat :
          s.namespace == ns_name ? s.service_id : null
        ]) :
        svc_name => {
          endpoints = {
            for ep in [
              for s in var.services_flat :
              s if s.namespace == ns_name && s.service_id == svc_name
            ] :
            ep.endpoint_id => {
              address  = ep.address
              port     = ep.port
              metadata = ep.metadata
              network = coalesce(
                try(ep.network, null),
                try(ep.metadata["network"], null)
              )
            }
          }
        }
      }
    }
  }

  services_flat = merge([
    for ns_name, ns in local.namespaces : {
      for svc_id, svc in ns.services :
      "${ns_name}/${svc_id}" => {
        namespace_id = ns_name
        service_id   = svc_id
        endpoints    = svc.endpoints
      }
    }
  ]...)

  monitored_services = var.enable_uptime_checks ? local.services_flat : {}
  alerting_services = (
    var.enable_uptime_checks && length(var.notification_channels) > 0
  ) ? local.monitored_services : {}
}

resource "google_service_directory_service" "svc" {
  for_each = local.services_flat

  service_id = each.value.service_id
  namespace  = google_service_directory_namespace.ns[each.value.namespace_id].id
}

# ─────────────────────────────────────────────────────────────
# 3. Endpoints
# ─────────────────────────────────────────────────────────────
locals {
  endpoints_flat = merge([
    for key, svc in local.services_flat : {
      for ep_id, ep in svc.endpoints :
      "${key}/${ep_id}" => {
        namespace_id = svc.namespace_id
        service_id   = svc.service_id
        endpoint_id  = ep_id
        address      = ep.address
        port         = ep.port
        metadata     = ep.metadata
        network      = try(ep.network, null)
      }
    }
  ]...)
}

resource "google_service_directory_endpoint" "ep" {
  for_each = local.endpoints_flat

  endpoint_id = each.value.endpoint_id
  service     = google_service_directory_service.svc["${each.value.namespace_id}/${each.value.service_id}"].id
  address     = each.value.address
  port        = each.value.port
  metadata    = each.value.metadata
  network     = each.value.network
}

# ─────────────────────────────────────────────────────────────
# 4. Uptime checks 
# ─────────────────────────────────────────────────────────────
resource "google_monitoring_uptime_check_config" "sd" {
  for_each = local.monitored_services

  project      = var.project
  display_name = "${each.value.namespace_id}-${each.value.service_id} ${var.suffix}"
  checker_type = "VPC_CHECKERS"
  timeout      = coalesce(var.uptime_defaults.timeout, "10s")
  period       = coalesce(var.uptime_defaults.period, "60s")

  monitored_resource {
    type = "servicedirectory_service"
    labels = {
      project_id     = var.project
      location       = var.location
      namespace_name = each.value.namespace_id
      service_name   = each.value.service_id
    }
  }

  tcp_check {
    port = tonumber(try(values(each.value.endpoints)[0].port, 80))
  }

  depends_on = [
    google_service_directory_endpoint.ep,
    google_service_directory_service.svc
  ]

  //dynamic "selected_regions" {
  //  for_each = var.uptime_defaults.selected_regions
  //  content  = selected_regions.value
  //}
  selected_regions = ["usa-iowa", "usa-oregon", "usa-virginia"]
}

# ─────────────────────────────────────────────────────────────
# 5. Alert policies
# ─────────────────────────────────────────────────────────────
resource "google_monitoring_alert_policy" "uptime" {
  for_each = local.alerting_services
  project  = var.project

  display_name          = "ALERT sd-${each.value.namespace_id}-${each.value.service_id} down"
  combiner              = "OR"
  notification_channels = var.notification_channels
  severity              = "CRITICAL"

  conditions {
    display_name = "Failure of uptime check for: ${google_monitoring_uptime_check_config.sd[each.key].display_name}"
    condition_threshold {
      //filter = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.labels.check_id=\"${google_monitoring_uptime_check_config.sd[each.key].uptime_check_id}\" AND resource.type=\"uptime_url\""
      filter = trimspace(<<-EOT
        resource.type="servicedirectory_service"
        AND metric.type="monitoring.googleapis.com/uptime_check/check_passed"
        AND metric.labels.check_id="${google_monitoring_uptime_check_config.sd[each.key].uptime_check_id}"
      EOT
      )
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = var.alert_duration
      trigger { count = 1 }

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = []
      }
    }
  }

  documentation {
    subject = "Failed uptime check for service ${each.value.namespace_id}/${each.value.service_id}"
    content = <<-EOT
      Alert triggered when the uptime check for service `${each.value.namespace_id}/${each.value.service_id}` fails.
      This indicates that the service is not reachable or is down.

      Please check the service status and ensure it is operational. 
      
      IP: ${try(
        values(each.value.endpoints)[0].address,
        "unknown"
      )} -
      Port: ${try(
        values(each.value.endpoints)[0].port,
        "unknown"
      )}      
    EOT
  }

  user_labels = {
    module    = "internal-services-healthchecks"
    namespace = each.value.namespace_id
    service   = each.value.service_id
  }

  depends_on = [
    google_monitoring_uptime_check_config.sd
  ]
}
