#!/bin/bash

set -e
AGENT_ARN="arn:aws:bedrock-agentcore:us-east-1:206409480438:runtime/host_agent-nE2WdIG4fP"
BASE_NAME="${1:-kyc-agent}"
REGION="${2:-us-east-1}"
AGENT_ARN="${3:-$AGENT_ARN}"
VPC_STACK="${BASE_NAME}-vpc"
STORAGE_STACK="${BASE_NAME}-storage"
ROLES_STACK="${BASE_NAME}-roles"
MAIN_STACK="${BASE_NAME}-main"

if [ -z "$AGENT_ARN" ]; then
  echo "Error: AgentArn required. Pass as 3rd argument or set AGENT_ARN env var."
  exit 1
fi

echo "=========================================="
echo "Deploying KYC Main Stack"
echo "=========================================="
echo "VPC Stack: $VPC_STACK"
echo "Storage Stack: $STORAGE_STACK"
echo "Roles Stack: $ROLES_STACK"
echo "Main Stack: $MAIN_STACK"
echo "Region: $REGION"
echo "=========================================="

# Deploy VPC stack
echo ""
echo "[1/5] Deploying VPC stack..."
aws cloudformation deploy \
    --stack-name "$VPC_STACK" \
    --template-file templates/vpc-stack.yaml \
    --parameter-overrides StackName="$VPC_STACK" \
    --region "$REGION"
echo "✓ VPC stack ready"

# Deploy storage stack (S3 + DynamoDB)
echo ""
echo "[2/5] Deploying storage stack..."
aws cloudformation deploy \
    --stack-name "$STORAGE_STACK" \
    --template-file templates/storage-stack.yaml \
    --parameter-overrides StackName="$STORAGE_STACK" \
    --region "$REGION"
echo "✓ Storage stack ready"

# Get bucket name
SOURCE_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name "$STORAGE_STACK" \
    --query 'Stacks[0].Outputs[?OutputKey==`SourceBucketName`].OutputValue' \
    --output text \
    --region "$REGION")
echo "Source bucket: $SOURCE_BUCKET"

# Package and upload KYC processor Lambda (install deps from requirements.txt, then zip)
echo ""
echo "[3/5] Packaging and uploading KYC processor Lambda..."
TIMESTAMP=$(date +%s)
KYC_LAMBDA_ZIP_KEY="kyc-processor-${TIMESTAMP}.zip"
KYC_LAMBDA_DIR="lambda"
PACKAGE_DIR="${KYC_LAMBDA_DIR}/package"
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"
pip install -r "${KYC_LAMBDA_DIR}/requirements.txt" -t "$PACKAGE_DIR" --quiet --upgrade
cp "${KYC_LAMBDA_DIR}/kyc-processor.py" "$PACKAGE_DIR/"
python -c "
import zipfile, os
pkg = '$PACKAGE_DIR'
out = '$KYC_LAMBDA_ZIP_KEY'
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk(pkg):
        dirs[:] = [d for d in dirs if d != '__pycache__' and d != '.git']
        for f in files:
            if f.endswith('.pyc'): continue
            path = os.path.join(root, f)
            arcname = os.path.relpath(path, pkg)
            zf.write(path, arcname)
"
rm -rf "$PACKAGE_DIR"
aws s3 cp "$KYC_LAMBDA_ZIP_KEY" "s3://$SOURCE_BUCKET/$KYC_LAMBDA_ZIP_KEY" --region "$REGION"
rm "$KYC_LAMBDA_ZIP_KEY"
echo "✓ KYC processor Lambda uploaded: $KYC_LAMBDA_ZIP_KEY"

# Deploy roles stack (optional for KYC; kept for compatibility)
echo ""
echo "[4/5] Deploying roles stack..."
aws cloudformation deploy \
    --stack-name "$ROLES_STACK" \
    --template-file templates/roles-stack.yaml \
    --parameter-overrides StackName="$ROLES_STACK" BaseStackName="$BASE_NAME" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION"
echo "✓ Roles stack ready"

# Deploy main stack (KYC: DynamoDB, SQS, Lambda)
echo ""
echo "[5/5] Deploying main stack..."
aws cloudformation deploy \
    --stack-name "$MAIN_STACK" \
    --template-file templates/main-stack.yaml \
    --parameter-overrides \
        AgentArn="$AGENT_ARN" \
        StorageStackName="$STORAGE_STACK" \
        LambdaSourceBucket="$SOURCE_BUCKET" \
        LambdaSourceKey="$KYC_LAMBDA_ZIP_KEY" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION"
echo "✓ Main stack ready"

echo ""
echo "=========================================="
echo "✓ Deployment complete!"
echo "=========================================="
echo ""
aws cloudformation describe-stacks \
    --stack-name "$MAIN_STACK" \
    --query 'Stacks[0].Outputs' \
    --output table \
    --region "$REGION"
echo ""
echo "To delete: ./cleanup.sh $BASE_NAME $REGION"
