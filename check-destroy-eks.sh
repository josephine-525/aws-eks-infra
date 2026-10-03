#!/usr/bin/env bash
set -euo pipefail

# Post-destroy verification for expenseinfra (EKS path). Read-only AWS queries only;
# this script never runs terraform destroy or any delete API.
#
# GitLab destroy_apply removes everything in this project's Terraform state, including
# the application DynamoDB table (e.g. PREFIX-expenses), EKS cluster, VPC pieces, etc.
#
# Bootstrap resources are NOT in this Terraform project and are NOT deleted by
# destroy_apply: the S3 bucket in backend.tf (remote state) and the DynamoDB table
# used for state locking (dynamodb_table in backend.tf). Those persist until you
# delete them manually in AWS.
#
# Prometheus/Grafana/ArgoCD (installed by expenseapp's CI via Helm, not Terraform) need
# NO separate manual cleanup step: they run as ClusterIP-only Services with ephemeral
# (emptyDir) storage — no ELB, no EBS volume — so deleting the cluster removes them
# with nothing left behind in AWS. Only the CloudWatch Observability addon's log groups
# and Terraform-published SSM parameters are checked below (both Terraform-managed;
# should already be gone after destroy_apply — this just confirms it).
#
# Usage:
#   ./check-destroy-eks.sh --region ca-central-1 --prefix demoapp
# Optional:
#   --cluster-name demoapp-expense-eks
#
# ============================================================
# !! REQUIRED MANUAL STEPS BEFORE RUNNING THE DESTROY PIPELINE !!
# ============================================================
#
# Background: The ALB in EKS is dynamically created by the AWS Load Balancer
# Controller (LBC) in response to Kubernetes Ingress resources. It is NOT
# managed by Terraform. If you run destroy without removing the Ingress first,
# the ALB becomes an orphan resource and blocks VPC deletion, causing destroy
# to fail.
#
# --- Step 1: Point kubeconfig at the correct cluster ---
#
#   aws eks update-kubeconfig \
#     --name <PREFIX>-expense-eks \
#     --region <REGION>
#
#   kubectl config current-context   # confirm you are on the right cluster
#
# --- Step 2: Delete the Ingress so LBC tears down the ALB ---
#
#   kubectl delete ingress --all -n expense
#
#   # Alternatively, delete the entire namespace (removes Ingress, Services,
#   # and Deployments in one shot):
#   # kubectl delete namespace expense
#
# --- Step 3: Wait for the ALB to disappear (~1-3 minutes) ---
#
#   # Option A: poll with the AWS CLI until no k8s- prefixed ALB remains:
#   watch -n 5 "aws elbv2 describe-load-balancers --region <REGION> \
#     --query \"LoadBalancers[?contains(LoadBalancerName,'k8s-')].[LoadBalancerName,State.Code]\" \
#     --output table"
#
#   # Option B: check the AWS console manually:
#   #   EC2 -> Load Balancers -> filter by name containing "k8s-" and wait
#   #   until the entry is gone.
#
# --- Step 4: Trigger the destroy pipeline in GitLab ---
#
#   GitLab -> expenseinfra -> CI/CD -> Pipelines -> Run pipeline
#   Set: confirm_destroy = true, destroy_approval = YES_DESTROY_INFRA
#   Wait for destroy_plan to finish, then click destroy_apply ▶
#
# --- Step 5: After destroy completes, run this script to verify cleanup ---
#
#   ./check-destroy-eks.sh --region <REGION> --prefix <PREFIX>
#
# ============================================================

# Disable AWS CLI pager so script runs through end-to-end.
export AWS_PAGER=""

REGION="${AWS_REGION:-}"
PREFIX="${PREFIX:-}"
CLUSTER_NAME="${EKS_CLUSTER_NAME:-}"

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
    --cluster-name)
      CLUSTER_NAME="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 --region <aws-region> --prefix <name-prefix> [--cluster-name <eks-cluster>]"
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

if [[ -z "$CLUSTER_NAME" ]]; then
  CLUSTER_NAME="${PREFIX}-expense-eks"
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

echo "Region:       $REGION"
echo "Prefix:       $PREFIX"
echo "EKS cluster:  $CLUSTER_NAME"

run_table "EKS clusters" \
  aws eks list-clusters --region "$REGION" --output table

run_table "EKS nodegroups (for expected cluster)" \
  aws eks list-nodegroups --region "$REGION" --cluster-name "$CLUSTER_NAME" --output table

run_table "Load balancers matching prefix/k8s" \
  aws elbv2 describe-load-balancers --region "$REGION" \
    --query "LoadBalancers[?contains(LoadBalancerName, 'k8s') || contains(LoadBalancerName, '${PREFIX}')].[LoadBalancerName,State.Code,Type,VpcId]" \
    --output table

run_table "Target groups matching prefix/k8s" \
  aws elbv2 describe-target-groups --region "$REGION" \
    --query "TargetGroups[?contains(TargetGroupName, 'k8s') || contains(TargetGroupName, '${PREFIX}')].[TargetGroupName,Protocol,Port,VpcId]" \
    --output table

run_table "NAT gateways not deleted" \
  aws ec2 describe-nat-gateways --region "$REGION" \
    --query "NatGateways[?State!='deleted'].[NatGatewayId,State,VpcId,SubnetId]" \
    --output table

run_table "Elastic IP addresses" \
  aws ec2 describe-addresses --region "$REGION" \
    --query "Addresses[*].[AllocationId,PublicIp,AssociationId,NetworkInterfaceId]" \
    --output table

run_table "Network interfaces matching prefix/ELB/EKS" \
  aws ec2 describe-network-interfaces --region "$REGION" \
    --query "NetworkInterfaces[?contains(Description, 'ELB') || contains(Description, 'eks') || contains(Description, '${PREFIX}')].[NetworkInterfaceId,Status,Description,Attachment.InstanceId,VpcId]" \
    --output table

run_table "Non-default security groups matching prefix/k8s" \
  aws ec2 describe-security-groups --region "$REGION" \
    --query "SecurityGroups[?GroupName!='default' && (contains(GroupName, 'k8s') || contains(GroupName, '${PREFIX}'))].[GroupId,GroupName,VpcId]" \
    --output table

run_table "Internet gateways" \
  aws ec2 describe-internet-gateways --region "$REGION" \
    --query "InternetGateways[*].[InternetGatewayId,Attachments[0].VpcId]" \
    --output table

run_table "DynamoDB tables (app stack; excludes *terraform-locks*)" \
  aws dynamodb list-tables --region "$REGION" \
    --query "TableNames[?((contains(@, '${PREFIX}') || contains(@, 'expense')) && !contains(@, 'terraform-locks'))]" \
    --output table

run_table "ECR repositories matching prefix/expense" \
  aws ecr describe-repositories --region "$REGION" \
    --query "repositories[?contains(repositoryName, '${PREFIX}') || contains(repositoryName, 'expense')].[repositoryName,repositoryUri]" \
    --output table

run_table "CloudWatch Container Insights log groups (Terraform-managed, should be gone)" \
  aws logs describe-log-groups --region "$REGION" \
    --log-group-name-prefix "/aws/containerinsights/${CLUSTER_NAME}" \
    --query "logGroups[*].[logGroupName,retentionInDays]" \
    --output table

run_table "SSM parameters published for expenseapp CI (Terraform-managed, should be gone)" \
  aws ssm get-parameters-by-path --region "$REGION" \
    --path "/${PREFIX}/expense" --recursive \
    --query "Parameters[*].[Name]" \
    --output table

section "Bootstrap (expected to survive destroy_apply)"
echo "Remote state S3 bucket + DynamoDB state-lock table from backend.tf are not managed here."
echo "They should still exist after a successful destroy; only delete them manually if you intend to."

printf "\nDone. Review non-empty tables above as possible residue (bootstrap resources excluded from DynamoDB list).\n"
