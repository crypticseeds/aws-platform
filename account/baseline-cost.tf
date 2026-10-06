# Console-built cost guardrails, imported (DEV-134). Mirrors the live
# configuration, including budget amounts that differ from DEV-126.

# AWS-created default monitor and subscription (2023), imported as they are.
resource "aws_ce_anomaly_monitor" "default_services" {
  name              = "Default-Services-Monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

import {
  to = aws_ce_anomaly_monitor.default_services
  id = "arn:aws:ce::${data.aws_caller_identity.account_defaults.account_id}:anomalymonitor/c9e940b5-d9a9-4a0c-93dd-d721465c567e"
}

resource "aws_ce_anomaly_subscription" "default_services" {
  name             = "Default-Services-Subscription"
  frequency        = "DAILY"
  monitor_arn_list = [aws_ce_anomaly_monitor.default_services.arn]

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = ["5"]
    }
  }

  dynamic "subscriber" {
    for_each = toset(var.cost_alert_emails)
    content {
      type    = "EMAIL"
      address = subscriber.value
    }
  }
}

import {
  to = aws_ce_anomaly_subscription.default_services
  id = "arn:aws:ce::${data.aws_caller_identity.account_defaults.account_id}:anomalysubscription/bd27cfbb-db11-4863-8197-00632b4fd648"
}

locals {
  # Both monthly budgets are identical apart from name and limit.
  monthly_budgets = {
    "My Monthly Cost Budget - $10" = "10"
    "My Monthly Cost Budget - $20" = "20"
  }
}

resource "aws_budgets_budget" "monthly" {
  for_each = local.monthly_budgets

  name              = each.key
  budget_type       = "COST"
  limit_amount      = each.value
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2026-10-01_00:00"

  # Console filter: NOT RECORD_TYPE in (Credit, Refund).
  cost_types {
    include_credit = false
    include_refund = false
  }

  notification {
    notification_type          = "ACTUAL"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = var.cost_alert_emails
  }

  notification {
    notification_type          = "ACTUAL"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 85
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = var.cost_alert_emails
  }

  notification {
    notification_type          = "FORECASTED"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = var.cost_alert_emails
  }
}

import {
  for_each = local.monthly_budgets
  to       = aws_budgets_budget.monthly[each.key]
  id       = "${data.aws_caller_identity.account_defaults.account_id}:${each.key}"
}

resource "aws_budgets_budget" "zero_spend" {
  name              = "My Zero-Spend Budget"
  budget_type       = "COST"
  limit_amount      = "1"
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2023-06-01_00:00"

  notification {
    notification_type          = "ACTUAL"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 0.01
    threshold_type             = "ABSOLUTE_VALUE"
    subscriber_email_addresses = var.cost_alert_emails
  }
}

import {
  to = aws_budgets_budget.zero_spend
  id = "${data.aws_caller_identity.account_defaults.account_id}:My Zero-Spend Budget"
}
