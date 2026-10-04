output "ci_plan_role_arn" {
  description = "ARN of the plan-only CI role. Set as the AWS_ROLE_ARN repository variable for the plan workflow (DEV-135)."
  value       = aws_iam_role.ci_plan.arn
}

output "github_oidc_provider_arn" {
  description = "ARN of the account-wide GitHub Actions OIDC provider. Other projects' CI roles trust this same provider."
  value       = aws_iam_openid_connect_provider.github.arn
}
