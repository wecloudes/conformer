# Framework manifest — FedRAMP (NIST SP 800-53 baseline).
#
# A framework is a NAMED BUNDLE of transformation units (ADR-009). The build
# pipeline expands this list and applies each unit from transformations/<name>/.
# Units that have no rules for the module being built are simply skipped, so the
# same bundle hardens any module (generic units) plus the modules it has bindings
# for (aws-* units). Keep `transformations` a flat list of quoted unit names.

description = "FedRAMP (NIST SP 800-53 baseline)"

transformations = [
  "avm-secure-defaults",
  "aws-secure-defaults",
  "destroy",
  "tags",
  "aws-s3-public-access",
  "aws-s3-checks-fedramp",
  "aws-rds-harden",
  "aws-eks-audit-logs",
  "aws-vpc-flow-logs",
  "aws-ebs-encryption",
  "aws-efs-encryption",
  "aws-docdb-encryption",
  "aws-neptune-encryption",
  "aws-redshift-harden",
  "aws-elasticache-encryption",
  "aws-dynamodb-encryption",
  "aws-kms-rotation",
  "aws-cloudtrail-harden",
  "aws-ecr-harden",
  "aws-ec2-imdsv2",
  "aws-sqs-encryption",
  "aws-cloudwatch-log-retention",
  "aws-opensearch-harden",
  "aws-apigateway-harden",
  "aws-alb-harden",
  "aws-cloudfront-https",
  "aws-lambda-tracing",
  "aws-msk-encryption",

  # --- Azure (azurerm) equivalents ---
  "azure-storage-harden",
  "azure-manageddisk-harden",
  "azure-cdn-https",
  "azure-keyvault-harden",
  "azure-keyvault-key-rotation",
  "azure-loganalytics-retention",
  "azure-acr-harden",
  "azure-aks-harden",
  "azure-functionapp-harden",
  "azure-appservice-harden",
  "azure-cosmosdb-harden",
  "azure-redis-harden",
  "azure-mssql-harden",
  "azure-eventhub-harden",
  "azure-servicebus-harden",
  "azure-search-harden",
]
