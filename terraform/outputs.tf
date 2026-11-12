output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "ecr_repository_url" {
  description = "ECR repository URL — use this as IMAGE_DOCKER_REPO in the app repo's GitHub Actions secrets"
  value       = aws_ecr_repository.erpal_app.repository_url
}

output "aws_region" {
  description = "AWS region the resources were deployed to"
  value       = var.aws_region
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "github_actions_role_arn" {
  description = "IAM Role ARN for GitHub Actions OIDC — add as AWS_ROLE_ARN secret in both repositories"
  value       = aws_iam_role.github_actions_deploy.arn
}

output "configure_kubectl" {
  description = "Run this command after apply to configure kubectl"
  value       = "aws eks --region ${var.aws_region} update-kubeconfig --name ${module.eks.cluster_name}"
}
