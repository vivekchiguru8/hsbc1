# hsbc1

## GKE management server

Terraform creates a Debian management VM in `asia-south1-a` with no public IP.
SSH is allowed through Identity-Aware Proxy (IAP), and the VM's dedicated service
account is authorized to administer the GKE cluster.

Before connecting, your user account needs the following project roles:

- `roles/iap.tunnelResourceAccessor`
- `roles/compute.osLogin`
- `roles/compute.viewer`

After applying Terraform, connect using the `management_server_ssh_command`
output, or run:

```powershell
gcloud compute ssh gke-management --zone asia-south1-a --project project-10094705-9153-43d5-bb8 --tunnel-through-iap
```

The startup script installs `gcloud`, `kubectl`, and the GKE auth plugin. Once
SSH'd into the VM, get cluster credentials and verify access:

```bash
gcloud container clusters get-credentials my-gke-cluster --zone asia-south1-a --project project-10094705-9153-43d5-bb8
kubectl get nodes
```