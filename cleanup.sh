#!/bin/bash
# Empty S3 buckets and delete CloudFormation stacks one by one (reverse dependency order).
# Usage: ./cleanup.sh [BASE_NAME] [REGION]
# Example: ./cleanup.sh kyc-agent us-east-1

set -e

BASE_NAME="${1:-kyc-agent}"
REGION="${2:-us-east-1}"
VPC_STACK="${BASE_NAME}-vpc"
STORAGE_STACK="${BASE_NAME}-storage"
ROLES_STACK="${BASE_NAME}-roles"
MAIN_STACK="${BASE_NAME}-main"

echo "=========================================="
echo "Cleanup: empty S3 buckets, then delete stacks"
echo "=========================================="
echo "Main Stack:   $MAIN_STACK"
echo "Roles Stack:  $ROLES_STACK"
echo "Storage Stack: $STORAGE_STACK"
echo "VPC Stack:    $VPC_STACK"
echo "Region:       $REGION"
echo "=========================================="

# [1/4] Delete main stack first (depends on storage + roles)
echo ""
echo "[1/4] Deleting main stack..."
if aws cloudformation describe-stacks --stack-name "$MAIN_STACK" --region "$REGION" &>/dev/null; then
    aws cloudformation delete-stack --stack-name "$MAIN_STACK" --region "$REGION"
    aws cloudformation wait stack-delete-complete --stack-name "$MAIN_STACK" --region "$REGION"
    echo "✓ Main stack deleted"
else
    echo "  (stack does not exist, skipping)"
fi

# [2/4] Delete roles stack
echo ""
echo "[2/4] Deleting roles stack..."
if aws cloudformation describe-stacks --stack-name "$ROLES_STACK" --region "$REGION" &>/dev/null; then
    aws cloudformation delete-stack --stack-name "$ROLES_STACK" --region "$REGION"
    aws cloudformation wait stack-delete-complete --stack-name "$ROLES_STACK" --region "$REGION"
    echo "✓ Roles stack deleted"
else
    echo "  (stack does not exist, skipping)"
fi

# [3/4] Empty S3 bucket from storage stack, then delete storage stack
echo ""
echo "[3/4] Emptying S3 bucket(s) and deleting storage stack..."
SOURCE_BUCKET=""
if aws cloudformation describe-stacks --stack-name "$STORAGE_STACK" --region "$REGION" &>/dev/null; then
    SOURCE_BUCKET=$(aws cloudformation describe-stacks \
        --stack-name "$STORAGE_STACK" \
        --query 'Stacks[0].Outputs[?OutputKey==`SourceBucketName`].OutputValue' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "")
fi

if [ -n "$SOURCE_BUCKET" ]; then
    echo "  Emptying bucket: $SOURCE_BUCKET"
    aws s3 rm "s3://$SOURCE_BUCKET" --recursive --region "$REGION" 2>/dev/null || true
    echo "  ✓ Bucket emptied"
fi

if aws cloudformation describe-stacks --stack-name "$STORAGE_STACK" --region "$REGION" &>/dev/null; then
    aws cloudformation delete-stack --stack-name "$STORAGE_STACK" --region "$REGION"
    aws cloudformation wait stack-delete-complete --stack-name "$STORAGE_STACK" --region "$REGION"
    echo "✓ Storage stack deleted"
else
    echo "  (stack does not exist, skipping)"
fi

# [4/4] Delete VPC stack
echo ""
echo "[4/4] Deleting VPC stack..."
if aws cloudformation describe-stacks --stack-name "$VPC_STACK" --region "$REGION" &>/dev/null; then
    aws cloudformation delete-stack --stack-name "$VPC_STACK" --region "$REGION"
    aws cloudformation wait stack-delete-complete --stack-name "$VPC_STACK" --region "$REGION"
    echo "✓ VPC stack deleted"
else
    echo "  (stack does not exist, skipping)"
fi

echo ""
echo "=========================================="
echo "✓ Cleanup complete"
echo "=========================================="
