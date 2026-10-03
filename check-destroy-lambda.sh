#!/usr/bin/env bash
set -euo pipefail

# Post-destroy verification for expenseinfra (lambda path). Read-only AWS queries only;
# this script never runs terraform destroy or any delete API.
#
# GitLab destroy_apply removes everything in this project's Terraform state, including
# the application DynamoDB table (e.g. PREFIX-expenses), Lambda, API Gateway, etc.
#
# Bootstrap resources are NOT in this Terraform project and are NOT deleted by
# destroy_apply: the S3 bucket in backend.tf (remote state) and the DynamoDB table
# used for state locking (dynamodb_table in backend.tf). Those persist until you
# delete them manually in AWS.
#
# Usage:
#   ./check-destroy-lambda.sh --region ca-central-1 --prefix demoapp

export AWS_PAGER=""

REGION="${AWS_REGION:-}"
PREFIX="${PREFIX:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      REGION="${2:-}"
      shift 2
      ;;
    --prefix)
      PREFIX="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 --region <aws-region> --prefix <name-prefix>"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$REGION" ]]; then
  echo "ERROR: region is required (set --region or AWS_REGION)." >&2
  exit 1
fi

if [[ -z "$PREFIX" ]]; then
  echo "ERROR: prefix is required (set --prefix or PREFIX)." >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "ERROR: aws CLI not found in PATH." >&2
  exit 1
fi

section() {
  printf "\n==== %s ====\n" "$1"
}

run_table() {
  local label="$1"
  shift
  section "$label"
  if ! "$@"; then
    echo "(command failed; continuing)"
  fi
}

echo "Region: $REGION"
echo "Prefix: $PREFIX"

# Lambda function
run_table "Lambda functions matching prefix" \
  aws lambda list-functions --region "$REGION" \
    --query "Functions[?contains(FunctionName, '${PREFIX}') || contains(FunctionName, 'expense')].[FunctionName,Runtime,LastModified]" \
    --output table

# API Gateway v2
run_table "API Gateway v2 (HTTP APIs) matching prefix" \
  aws apigatewayv2 get-apis --region "$REGION" \
    --query "Items[?contains(Name, '${PREFIX}') || contains(Name, 'expense')].[Name,ApiId,ProtocolType,CreatedDate]" \
    --output table

# S3 buckets matching prefix (frontend bucket has random suffix)
run_table "S3 buckets matching prefix" \
  aws s3api list-buckets \
    --query "Buckets[?contains(Name, '${PREFIX}') || contains(Name, 'expense')].[Name,CreationDate]" \
    --output table

# CloudFront distributions
run_table "CloudFront distributions matching prefix" \
  aws cloudfront list-distributions \
    --query "DistributionList.Items[?contains(Comment, '${PREFIX}') || contains(Comment, 'expense')].[Id,DomainName,Status,Comment]" \
    --output table

# IAM roles matching prefix
run_table "IAM roles matching prefix (lambda)" \
  aws iam list-roles \
    --query "Roles[?contains(RoleName, '${PREFIX}') || contains(RoleName, 'expense')].[RoleName,CreateDate]" \
    --output table

# App DynamoDB only (exclude Terraform state lock table name pattern).
run_table "DynamoDB tables (app stack; excludes *terraform-locks*)" \
  aws dynamodb list-tables --region "$REGION" \
    --query "TableNames[?((contains(@, '${PREFIX}') || contains(@, 'expense')) && !contains(@, 'terraform-locks'))]" \
    --output table

# ECR repositories
run_table "ECR repositories matching prefix" \
  aws ecr describe-repositories --region "$REGION" \
    --query "repositories[?contains(repositoryName, '${PREFIX}') || contains(repositoryName, 'expense')].[repositoryName,repositoryUri]" \
    --output table

# SSM parameter
run_table "SSM parameters matching prefix" \
  aws ssm describe-parameters --region "$REGION" \
    --query "Parameters[?contains(Name, '${PREFIX}') || contains(Name, 'expense')].[Name,Type,LastModifiedDate]" \
    --output table

# SNS topics
run_table "SNS topics matching prefix" \
  aws sns list-topics --region "$REGION" \
    --query "Topics[?contains(TopicArn, '${PREFIX}') || contains(TopicArn, 'expense')].[TopicArn]" \
    --output table

# Budget
run_table "AWS Budgets matching prefix" \
  aws budgets describe-budgets \
    --account-id "$(aws sts get-caller-identity --query Account --output text)" \
    --query "Budgets[?contains(BudgetName, '${PREFIX}') || contains(BudgetName, 'expense')].[BudgetName,BudgetLimit.Amount,BudgetLimit.Unit]" \
    --output table

section "Bootstrap (expected to survive destroy_apply)"
echo "Remote state S3 bucket + DynamoDB state-lock table from backend.tf are not managed here."
echo "They should still exist after a successful destroy; only delete them manually if you intend to."

printf "\nDone. Review non-empty tables above as possible residue (bootstrap resources excluded from DynamoDB list).\n"
