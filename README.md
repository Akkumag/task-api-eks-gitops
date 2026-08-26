# task-api-eks-gitops

A small Task API deployed to **Amazon EKS** using **GitOps (ArgoCD)**, with **Prometheus + Grafana** monitoring — built as a portfolio project to demonstrate an end-to-end cloud-native deployment pipeline.

## Architecture

```
Terraform  →  VPC + EKS cluster + ECR repository (AWS)
Docker     →  task-api image built and pushed to ECR
ArgoCD     →  watches this repo, deploys:
                 ├── task-api (Deployment, Service)      from gitops/manifests/
                 └── kube-prometheus-stack (Helm chart)  from gitops/argocd/monitoring-application.yaml
Prometheus →  scrapes task-api's /metrics via a ServiceMonitor
Grafana    →  visualizes those metrics (Prometheus pre-provisioned as a datasource)
```

## Repo layout

```
app/                    Node.js/Express Task API (source of truth for the image)
terraform/              VPC, EKS cluster + node group, ECR repository
gitops/manifests/       Plain Kubernetes manifests for task-api (namespace, deployment, service, servicemonitor)
gitops/argocd/          ArgoCD Application definitions (task-api, and kube-prometheus-stack via Helm)
```

## The app

Express API with an in-memory task store (not persistent — a deliberate tradeoff for a demo):

- `GET /healthz`, `GET /readyz` — liveness/readiness
- `GET /tasks`, `POST /tasks`, `PATCH /tasks/:id`, `DELETE /tasks/:id` — CRUD
- `GET /metrics` — Prometheus exposition format (`prom-client`), including a custom `tasks_created_total` counter

## Deploying from scratch

**Prerequisites:** an AWS account, AWS CLI configured, Terraform, `kubectl`, Docker, and a GitHub repo (this one, or your fork) that ArgoCD can reach.

1. **Provision the infrastructure**
   ```bash
   cd terraform
   terraform init
   terraform plan -out=tfplan
   terraform apply "tfplan"
   ```
   Creates the VPC, EKS cluster, node group, and ECR repository. Note the `ecr_repository_url` and `config_kubectl` outputs.

2. **Point kubectl at the new cluster**
   ```bash
   aws eks update-kubeconfig --region us-east-1 --name task-api-cluster
   ```

3. **Build and push the image** (note `--platform linux/amd64` — required if you're building on Apple Silicon; EKS nodes are amd64)
   ```bash
   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account_id>.dkr.ecr.us-east-1.amazonaws.com
   docker build --platform linux/amd64 -t <account_id>.dkr.ecr.us-east-1.amazonaws.com/task-api:latest app/
   docker push <account_id>.dkr.ecr.us-east-1.amazonaws.com/task-api:latest
   ```
   `gitops/manifests/deployment.yaml` ships with `<AWS_ACCOUNT_ID>` as a placeholder in the `image:` field — deliberately, and it **stays that way in git**: this repo is public, and an AWS account ID shouldn't sit in a public file unnecessarily. `gitops/argocd/application.yaml` has an `ignoreDifferences` entry for exactly that field, so ArgoCD never tries to sync/revert it. That means the running `image:` is set directly on the cluster after ArgoCD deploys (see step 7) rather than through git — a new image version is rolled out with `kubectl set image`, not `git push`. That's the deliberate tradeoff for keeping the account ID out of the public repo.

4. **Install ArgoCD into the cluster**
   ```bash
   kubectl create namespace argocd
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   ```

5. **Install the Prometheus Operator CRDs directly** (they're too large for ArgoCD's client-side apply — see Gotchas below)
   ```bash
   for f in alertmanagerconfigs alertmanagers podmonitors probes prometheusagents prometheuses prometheusrules scrapeconfigs servicemonitors thanosrulers; do
     kubectl apply --server-side --force-conflicts -f "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.77.2/example/prometheus-operator-crd/monitoring.coreos.com_${f}.yaml"
   done
   ```

6. **Deploy task-api and monitoring via ArgoCD**
   ```bash
   kubectl apply -f gitops/argocd/application.yaml -f gitops/argocd/monitoring-application.yaml
   ```
   Both `Application` resources have `syncPolicy.automated`, so they'll sync themselves. Check status with:
   ```bash
   kubectl get applications -n argocd
   ```

7. **Point the Deployment at the real image**

   The Deployment ArgoCD just created is still running the literal `<AWS_ACCOUNT_ID>...` placeholder (it'll fail to start — `InvalidImageName`, not just a bad pull). Patch it directly:
   ```bash
   kubectl set image deployment/task-api task-api=<account_id>.dkr.ecr.us-east-1.amazonaws.com/task-api:latest -n task-api
   ```
   Thanks to the `ignoreDifferences` entry, ArgoCD won't revert this or flag it as drift on anything else — the Application will just show `OutOfSync` for this one field forever, which is expected.

8. **Verify**
   ```bash
   kubectl port-forward -n task-api svc/task-api 8080:80
   curl localhost:8080/healthz
   ```
   Grafana: `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80`, credentials in the `kube-prometheus-stack-grafana` secret (`admin-user` / `admin-password` keys).

## Gotchas hit while building this

- **Free-tier instance restriction.** New/trial AWS accounts may only allow launching free-tier-eligible EC2 types. `t3.medium` failed with `InvalidParameterCombination`; the node group uses `t3.small`.
- **Pods-per-node limit.** `t3.small` supports ~11 pods per node (AWS VPC CNI, ENI-based). The full monitoring stack + task-api didn't fit on 2 nodes — the node group runs 3.
- **CRDs too large for client-side apply.** The Prometheus Operator CRDs (bundled in the `kube-prometheus-stack` Helm chart) exceed Kubernetes' 262144-byte annotation limit under `kubectl apply` (client-side). ArgoCD's `ServerSideApply=true` sync option does **not** cover CRDs in this ArgoCD version — worked around by setting `helm.skipCrds: true` on the Application and installing the CRDs separately with `kubectl apply --server-side`.
- **Operator needs a restart after CRDs land late.** If the operator pod started before its CRDs existed, it won't pick them up — `kubectl rollout restart deployment/kube-prometheus-stack-operator -n monitoring`.
- **Architecture mismatch.** Building the Docker image on Apple Silicon without `--platform linux/amd64` produces an arm64 image that won't run on (amd64) EKS nodes.

## Tearing down

```bash
cd terraform
terraform destroy
```
Empty the ECR repository first if it still has images — `aws_ecr_repository` may refuse to delete a non-empty repo.
