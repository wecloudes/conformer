# Framework manifest — SOC 2 Type II (Trust Services Criteria).
#
# A framework is a NAMED BUNDLE of transformation units (ADR-009). Differs from
# CIS only in the S3 plan-time checks (adds A1.2 replication advisory). All
# structural units are shared. Keep `transformations` a flat list of quoted
# unit names.

description = "SOC 2 Type II"

transformations = [
  "avm-secure-defaults",
  "aws-secure-defaults",
  "destroy",
  "tags",
  "aws-s3-public-access",
  "aws-s3-checks-soc2",
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
