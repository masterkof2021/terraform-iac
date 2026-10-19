# Configuración independiente: protege el bucket incluso al destruir el laboratorio.
terraform {
  required_version = ">= 1.11.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  allowed_account_ids = ["222234418877"]
  region              = "us-east-2"
  default_tags {
    tags = {
      Project   = "globomatics"
      ManagedBy = "OpenTofu"
      Purpose   = "SharedState"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  bucket_name = "globomatics-tofu-state-${data.aws_caller_identity.current.account_id}-us-east-2"
}

# Usuarios IAM que reciben acceso al estado compartido. Para sumar a un
# companero solo hay que anadir su usuario a esta lista y aplicar el modulo.
variable "shared_state_users" {
  description = "Usuarios IAM que se agregan al grupo globomatics-shared-state."
  type        = list(string)
  default     = ["opentofu", "usuario1", "usuario2"]
}

variable "shared_state_aws_managed_policies" {
  description = "Politicas administradas por AWS que el grupo necesita para operar el laboratorio."
  type        = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonEC2FullAccess",
    "arn:aws:iam::aws:policy/AmazonVPCFullAccess",
  ]
}

variable "shared_state_extra_policy_arns" {
  description = "ARNs de politicas propias ya existentes en la cuenta (por ejemplo OpenTofuReadAmazonLinuxAMI, OpenTofuResourceGroupsCreate y OpenTofuTagGlobomaticsResourceGroup)."
  type        = list(string)
  default     = []
}

resource "aws_s3_bucket" "state" {
  bucket        = local.bucket_name
  force_destroy = false
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.state]
}

# Acceso compartido: un grupo IAM concentra los permisos y cada companero se
# agrega al grupo en lugar de recibir una politica individual por usuario.
resource "aws_iam_group" "shared_state" {
  name = "globomatics-shared-state"
  path = "/"
}

# Politica insertada del grupo: acceso al estado compartido (OpenTofu y Pulumi).
resource "aws_iam_group_policy" "state_access" {
  name   = "globomatics-shared-state"
  group  = aws_iam_group.shared_state.name
  policy = file("${path.module}/../iam/state-access.json")
}

resource "aws_iam_group_policy_attachment" "aws_managed" {
  for_each   = toset(concat(var.shared_state_aws_managed_policies, var.shared_state_extra_policy_arns))
  group      = aws_iam_group.shared_state.name
  policy_arn = each.value
}

resource "aws_iam_user_group_membership" "shared_state" {
  for_each = toset(var.shared_state_users)
  user     = each.value
  groups   = [aws_iam_group.shared_state.name]
}

output "state_bucket" {
  value = aws_s3_bucket.state.id
}

output "state_access_group" {
  description = "Grupo IAM que recibe los permisos del estado compartido."
  value       = aws_iam_group.shared_state.name
}

output "state_access_policy_name" {
  description = "Nombre de la politica insertada del grupo."
  value       = aws_iam_group_policy.state_access.name
}

output "state_access_users" {
  description = "Usuarios agregados al grupo del estado compartido."
  value       = sort(var.shared_state_users)
}
