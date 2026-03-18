---
name: clusters
description: >
  Multi-cluster reference data for troubleshooting across EMEA, APAC, NAM.
  Contains kubectl contexts, ArgoCD cluster names, and Azure Application
  Insights details per region. Auto-loaded by the troubleshooter agent.
disable-model-invocation: true
---

## Cluster Registry

Edit the values below to match your environment.

### Clusters

| Region | kubectl Context | ArgoCD Cluster Name | Azure Resource Group | App Insights Instance |
|--------|----------------|---------------------|---------------------|-----------------------|
| EMEA   | `aks-emea-prod` | `emea-production` | `rg-emea-prod` | `ai-emea-prod` |
| APAC   | `aks-apac-prod` | `apac-production` | `rg-apac-prod` | `ai-apac-prod` |
| NAM    | `aks-nam-prod`  | `nam-production`  | `rg-nam-prod`  | `ai-nam-prod`  |

### ArgoCD
Single instance manages all 3 clusters. App naming: `<service>-<region>`.
Each app's `destination.server` identifies the target cluster.

### kubectl — Target a Specific Cluster
```bash
kubectl --context=aks-emea-prod get pods -n <namespace>
kubectl --context=aks-apac-prod logs deployment/<app> --tail=200
kubectl --context=aks-nam-prod get events -n <namespace>
```

### Azure App Insights — Query Per Region
```bash
az monitor app-insights query \
  --app ai-<region>-prod --resource-group rg-<region>-prod \
  --analytics-query "<KQL>"
```

### Cross-Region Comparison
```bash
for region in emea apac nam; do
  echo "=== $region ==="
  kubectl --context="aks-${region}-prod" get pods -n <ns> -l app=<svc>
done
```

```bash
for region in emea apac nam; do
  echo "=== $region ==="
  az monitor app-insights query \
    --app "ai-${region}-prod" --resource-group "rg-${region}-prod" \
    --analytics-query "exceptions | where timestamp > ago(2h) | summarize count() by type"
done
```
