variable "cost_alert_emails" {
  description = "Email addresses subscribed to the budget notifications and the Cost Anomaly Detection subscription. Personal data in a public repo, so no default: supply it as TF_VAR_cost_alert_emails (a JSON list, e.g. [\"a@example.com\"])."
  type        = list(string)
  sensitive   = true
}
