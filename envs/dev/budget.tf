# Project cost alert (DEV-126): emails when this project's spend in the month
# passes $30, and again at $50, so a forgotten or runaway environment can be
# destroyed. It belongs to this root on purpose: `terraform destroy` removes it
# together with the resources it watches, and the next apply brings it back.
# The account's own console budgets are separate and are not managed here.
#
# "This project" means cost tagged Project=aws-platform (local.tags, set by the
# provider's default_tags and passed to the modules and the Load Balancer
# Controller). Two limits follow from that:
#  - The Project tag must be ACTIVE as a cost allocation tag in Billing. That
#    is an account setting the owner turns on once (docs/runbooks/deploy.md,
#    section 2). Until it is active the filter matches nothing and this budget
#    never alerts.
#  - Untagged cost (some data transfer, tax) is not counted.
#
# Budgets refreshes a few times a day and tag data lags by up to a day, so an
# alert arrives hours after the spend, not instantly. Credits and refunds are
# excluded, like the account's console budgets, so spend is counted gross.
locals {
  # Dollars per month. The first alert is the early warning, the second the cap.
  budget_warn_usd = 30
  budget_max_usd  = 50
}

resource "aws_budgets_budget" "project" {
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(local.budget_max_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Tag filters take the form user:<key>$<value>.
  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:Project$%s", local.tags.Project)]
  }

  cost_types {
    include_credit = false
    include_refund = false
  }

  notification {
    notification_type          = "ACTUAL"
    comparison_operator        = "GREATER_THAN"
    threshold                  = local.budget_warn_usd
    threshold_type             = "ABSOLUTE_VALUE"
    subscriber_email_addresses = var.cost_alert_emails
  }

  notification {
    notification_type          = "ACTUAL"
    comparison_operator        = "GREATER_THAN"
    threshold                  = local.budget_max_usd
    threshold_type             = "ABSOLUTE_VALUE"
    subscriber_email_addresses = var.cost_alert_emails
  }
}
