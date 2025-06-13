# Internal Services Healthchecks

This Terraform module configures **Uptime Checks** and **Alert Policies** for internal services registered in Google Cloud's Service Directory. It ensures that services are monitored for availability and sends alerts when issues are detected.

## Features

- **Uptime Checks**: Monitors the availability of services using TCP checks.
- **Alert Policies**: Sends critical alerts when uptime checks fail.
- **Service Directory Integration**: Targets services registered in Service Directory.

---

## Prerequisites

- Google Cloud Platform (GCP) project.
- Services registered in **Service Directory**.
- Notification channels configured in GCP Monitoring.

---

## Inputs

| Name                          | Type   | Description                                                                 | Required |
|-------------------------------|--------|-----------------------------------------------------------------------------|----------|
| `project`                     | String | The GCP project ID.                                                        | Yes      |
| `location`                    | String | The location of the Service Directory resources.                           | Yes      |
| `uptime_defaults.selected_regions` | List  | List of regions for uptime checks.                                         | Yes      |
| `notification_channels`       | List  | Notification channels for alert policies.                                  | Yes      |
| `alerting_services`           | Map   | Map of services to monitor, including namespace and service IDs.           | Yes      |

---

## Outputs

| Name                  | Description                                                                 |
|-----------------------|-----------------------------------------------------------------------------|
| `uptime_check_configs`| The configured uptime checks for the monitored services.                   |
| `alert_policies`      | The alert policies created for the monitored services.                     |

---

## Usage

```terraform
module "internal-services-healthchecks" {
  source  = "ifgiovanni/internal-services-healthchecks/gcp"
  version = "0.0.1"

  project                     = "my-gcp-project"
  location                    = "us-central1"
  uptime_defaults.selected_regions = ["usa-iowa", "usa-oregon", "usa-virginia"]
  notification_channels       = ["projects/my-gcp-project/notificationChannels/123456"]
  services_flat = [
    {
      namespace   = "databases"
      service_id  = "redis-svc"
      endpoint_id = "redis-svc-container"
      address     = "127.0.0.1"
      port        = 6380
      metadata = {
        stage   = "prod"
        region  = "us-east1"
        vm      = "loki"
      }
      network = "projects/my-gcp-project/locations/global/networks/vpc-example"
    }
  ]
}

---

## How It Works

### Uptime Checks
- **Monitored Resource**: Targets services registered in Service Directory.
- **TCP Check**: Performs a TCP check on the specified port (default: 80 if not provided).
- **Regions**: Executes checks in the specified regions.

### Alert Policies
- **Conditions**: Alerts are triggered when uptime checks fail.
- **Severity**: Alerts are marked as `CRITICAL`.
- **Notification Channels**: Sends alerts to the specified channels.