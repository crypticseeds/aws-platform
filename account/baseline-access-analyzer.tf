# Account baseline: the IAM Access Analyzer (external access, account zone) and
# its archive rule, built in the console and imported here (DEV-134). Mirrors the
# live configuration; the import blocks can be removed after the first apply.

resource "aws_accessanalyzer_analyzer" "external" {
  analyzer_name = "ExternalAccessAnalyzer"
  type          = "ACCOUNT"
}

import {
  to = aws_accessanalyzer_analyzer.external
  id = "ExternalAccessAnalyzer"
}

# Archives findings for the roles Identity Center provisions (federated
# principal contains AWSSSO_), which are expected, not external access.
resource "aws_accessanalyzer_archive_rule" "identity_center_sso_roles" {
  analyzer_name = aws_accessanalyzer_analyzer.external.analyzer_name
  rule_name     = "identity-center-sso-roles"

  filter {
    criteria = "principal.Federated"
    contains = ["AWSSSO_"]
  }

  filter {
    criteria = "resourceType"
    eq       = ["AWS::IAM::Role"]
  }
}

import {
  to = aws_accessanalyzer_archive_rule.identity_center_sso_roles
  id = "ExternalAccessAnalyzer/identity-center-sso-roles"
}
