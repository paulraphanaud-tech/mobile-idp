resource "aws_secretsmanager_secret" "this" {
  for_each = var.secret_definitions

  name                    = each.key
  description             = each.value.description
  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Project = var.project_name
    Name    = each.key
  })
}
