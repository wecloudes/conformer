# Framework manifest — Spain ENS (Esquema Nacional de Seguridad), Royal Decree
# 311/2022. Mirrors the Azure Policy built-in regulatory-compliance initiative:
# https://learn.microsoft.com/en-us/azure/governance/policy/samples/spain-ens
#
# ENS is an Azure/government framework, so this bundle is the Azure generic units
# plus the cloud-agnostic units (tags/destroy/avm-secure-defaults). Each unit
# no-ops on a module that lacks its resource type. The aws-* units are
# deliberately excluded — ENS governs Azure workloads.
#
# Control mapping (real ENS v1 IDs from the initiative; "mp.com" = Protección de
# las comunicaciones, "op.acc" = Control de acceso, "op.exp" = Explotación):
#   mp.com.1  public network access off / firewall      -> *-harden public_network_access=false,
#             (storage, SQL, MySQL/PostgreSQL, Cosmos,      keyvault firewall, NSG flow logs (plan-gate)
#             Key Vault, App Gateway WAF)                   + App Gateway WAF assert (plan-gate)
#   mp.com.3  encryption / secure transfer in transit   -> storage secure-transfer + TLS1.2 floor on
#             (TLS, secure transfer to storage, TDE)        storage/cosmos/redis/eventhub/servicebus/
#                                                           mssql/cdn; SQL TLS + private (mssql)
#   mp.com.2/3 RBAC / access control / local auth        -> aks RBAC, local-auth off on cosmos/
#                                                           eventhub/servicebus/search
#   op.exp     logging & monitoring                      -> loganalytics 365d retention; APIM
#                                                           diagnostics + NSG flow logs (plan-gate)

description = "Spain ENS (Esquema Nacional de Seguridad, RD 311/2022)"

transformations = [
  "avm-secure-defaults",
  "destroy",
  "tags",
  # Azure (azurerm) hardening — ENS mp.com / op.acc / op.exp
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
