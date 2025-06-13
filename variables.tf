variable "project" {
  description = "GCP project ID"
  type        = string
}

variable "location" {
  description = "Region where the Service Directory is deployed"
  type        = string
  default     = "us-east1"
}

variable "services_flat" {
  description = "Flat list of services/endpoints to deploy"
  type = list(object({
    namespace   = string
    service_id  = string
    endpoint_id = string
    address     = string
    port        = number
    metadata    = map(string)
    network     = optional(string)
  }))
}

variable "enable_uptime_checks" {
  description = "If true, an uptime check is created for each Service Directory service"
  type        = bool
  default     = false
}

variable "uptime_defaults" {
  description = "Default parameters for the uptime check"
  type = object({
    period           = optional(string, "60s")
    timeout          = optional(string, "10s")
    selected_regions = optional(list(string), [])
  })
  default = {}
}

variable "notification_channels" {
  description = "List of full IDs of notification channels to use in all alerts"
  type        = list(string)
  default     = []
}

variable "alert_duration" {
  description = "Time the uptime check must fail before triggering the alert"
  type        = string
  default     = "120s"
}

variable "suffix" {
  description = "Optional suffix for the service names"
  type        = string
  default     = ""
}