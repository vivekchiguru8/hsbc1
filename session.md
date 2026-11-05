# HSBC GKE + VPA Pilot Session

## Date
2026-11-05

## Project Context
- Workspace: D:\HSBC\hsbc1
- Cluster: my-gke-cluster
- Project: project-10094705-9153-43d5-bb8
- Region/Zone: asia-south1 / asia-south1-a
- Namespace: vivek
- Deployment: nginx-deployment
- HPA: nginx-hpa
- VPA: nginx-vpa

## Objective
Set up and validate a Terraform-managed GKE cluster, deploy NGINX in the vivek namespace, enable HPA, and test Vertical Pod Autoscaler (VPA) in recommendation-only mode to evaluate the impact before broader rollout.

## Key Issues Encountered and Fixes
### 1. Terraform validation and resource configuration issues
- Duplicate kubernetes provider configuration
- Invalid provider setup and resource syntax
- Invalid `ports`, `limits`, and `requests` values in Kubernetes deployment
- Incorrect cluster autoscaling block requirements

### 2. GCP / IAM issues
- Wrong project ID used initially
- Incorrect billing / project access for the current account
- Permission denied while trying to access the project
- Service account mismatch for default compute service account

### 3. GKE/VPA operational issues
- Need to enable cluster-level VPA
- Need to confirm the VPA CRD exists in the cluster
- Need to create VPA in recommendation-only mode without editing deployment YAML files

## Corrected Configuration Summary
### Terraform cluster config (core idea)
- provider "google" with correct project ID
- `google_container_cluster.primary`
- `vertical_pod_autoscaling { enabled = true }`
- `cluster_autoscaling { resource_limits {...} }`
- `kubernetes_namespace.vivek`
- `kubernetes_deployment.nginx`
- `kubernetes_horizontal_pod_autoscaler_v2.nginx_hpa`

### Example cluster VPA block
```hcl
vertical_pod_autoscaling {
  enabled = true
}
```

## Commands Used
### Authentication / GCP
```powershell
gcloud auth list
gcloud auth login
gcloud config set project project-10094705-9153-43d5-bb8
gcloud projects describe project-10094705-9153-43d5-bb8
gcloud auth application-default login
```

### Terraform
```powershell
Set-Location "D:\HSBC\hsbc1"
terraform validate
terraform plan
terraform apply -auto-approve
```

### Kubernetes VPA creation
```powershell
kubectl api-resources | findstr /I vpa
@'
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: nginx-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: nginx-deployment
  updatePolicy:
    updateMode: "Off"
  resourcePolicy:
    containerPolicies:
    - containerName: nginx
      controlledResources:
      - cpu
      - memory
      minAllowed:
        cpu: 100m
        memory: 128Mi
      maxAllowed:
        cpu: 500m
        memory: 512Mi
'@ | kubectl -n vivek apply -f -
```

### Recommendation checking
```powershell
kubectl -n vivek get vpa
kubectl -n vivek describe vpa nginx-vpa
kubectl -n vivek top pod
kubectl top node
```

## VPA Pilot Status Before Cleanup
- VPA object was created in namespace vivek
- Mode used: Off
- Reason: recommendation-only mode for assessment without automatic resource updates
- This mode is appropriate for understanding recommendations before deciding to enable auto-update in production

## Cleanup Completed (2026-11-05)
- Deleted the `nginx-vpa` object from namespace `vivek`.
- Ran `terraform destroy -auto-approve`, removing the GKE cluster, namespace, NGINX deployment, and HPA.
- Verified `terraform state list` returned no managed resources.
- The Terraform configuration remains in the project and would recreate the infrastructure if applied again.

## Management Readout
The objective of the pilot is to validate whether VPA recommendations are beneficial for the workload and whether they create cost or operational risk on the broader cluster.

### What is being checked
- CPU and memory recommendation values from VPA
- Impact on HPA scaling behavior
- Node utilization and scheduling pressure
- Whether recommended requests align with actual workload demand
- Whether the recommendation leads to system stability without changing application behavior

### Expected outcomes
- Better resource allocation for the deployment
- Reduced risk of over- or under-provisioning
- Improved throughput efficiency at the cluster level
- Better insight before broader project rollout

## Final Conclusion
This pilot is useful as a low-risk recommendation-only validation. It allows engineering and management to review actual VPA suggestions before enabling broader automation across other projects.

## Save Location
- D:\HSBC\hsbc1\session.md
