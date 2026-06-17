# Framework manifest — Spain ENS (CCN) for AWS, ENS Categoría BÁSICA.
#
# Mirrors the AWS Config conformance pack
# Operational-Best-Practices-for-CCN-ENS-Low.yaml (awslabs/aws-config-rules),
# the CCN-CERT encoding of the Esquema Nacional de Seguridad (RD 311/2022) for
# AWS workloads. This is the AWS counterpart of the Azure `ens` framework.
#
# Honest scope: the three CCN-ENS packs are ~identical (112/113/114 Config rules)
# and differ only in DETECTIVE rules outside source-time forcing
# (ELBV2_ACM_CERTIFICATE_REQUIRED at Medium+High, GUARDDUTY_NON_ARCHIVED_FINDINGS
# at High). So all three ENS levels bundle the SAME force-able unit set below —
# the subset of pack rules conformer can enforce at source time or assert at plan
# time. The ELB ACM/TLS and WAF expectations are covered by the plan-gate asserts
# (run `scripts/plan-gate.sh tfplan ens_low`); GuardDuty is runtime-detective and
# out of scope (pair with AWS Config / GuardDuty itself).
#
# Mapped pack rules -> units: ENCRYPTED_VOLUMES->ebs; EFS_ENCRYPTED->efs;
# DYNAMODB_TABLE_ENCRYPTED_KMS->dynamodb; RDS_STORAGE_ENCRYPTED/
# RDS_INSTANCE_PUBLIC_ACCESS_CHECK->rds; REDSHIFT_*->redshift; OPENSEARCH_*->
# opensearch; CMK_BACKING_KEY_ROTATION_ENABLED->kms; CLOUD_TRAIL_*->cloudtrail;
# VPC_FLOW_LOGS_ENABLED->vpc-flow-logs; S3_BUCKET_*->s3-public-access +
# s3-checks-ens; ALB_*->alb-harden (+plan-gate ELB/WAF); API_GW_*->apigateway
# (+plan-gate APIGW logging); LAMBDA_*->lambda.

description = "Spain ENS (CCN) for AWS — ENS Categoría BÁSICA (RD 311/2022, CCN-ENS-Low pack)"

transformations = [
  "aws-secure-defaults",
  "destroy",
  "tags",
  "aws-s3-public-access",
  "aws-s3-checks-ens",
  "aws-rds-harden",
  "aws-ebs-encryption",
  "aws-efs-encryption",
  "aws-dynamodb-encryption",
  "aws-redshift-harden",
  "aws-opensearch-harden",
  "aws-kms-rotation",
  "aws-cloudtrail-harden",
  "aws-vpc-flow-logs",
  "aws-alb-harden",
  "aws-apigateway-harden",
  "aws-lambda-tracing",
]
