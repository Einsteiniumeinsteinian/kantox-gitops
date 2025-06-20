# ArgoCD Ingress Setup Script

A comprehensive bash script for setting up ArgoCD with AWS Load Balancer Controller ingress on Amazon EKS clusters. This script automates the deployment of ArgoCD ingress configuration using both static Kubernetes manifests and Helm charts with GitOps best practices.

## 🚀 Features

- **Automated Prerequisites Validation**: Checks for required tools and cluster connectivity
- **AWS Load Balancer Controller Installation**: Installs and configures AWS ALB controller
- **Dual Deployment Strategy**: Creates both static Kubernetes manifests and Helm charts
- **Multi-Environment Support**: Separate configurations for development, staging, and production
- **GitOps Integration**: Creates ArgoCD applications for self-managing infrastructure
- **GitHub Repository Integration**: Configures private repository access with PAT authentication
- **Flexible Deployment Options**: Choose between immediate deployment or configuration-only setup

## 📋 Prerequisites

### Required Tools

- `kubectl` - Kubernetes command-line tool
- `helm` - Helm package manager for Kubernetes
- `bash` - Bash shell (version 4.0+)

### AWS/EKS Requirements

- **EKS Cluster**: A running Amazon EKS cluster with kubectl access
- **OIDC Provider**: EKS cluster must have an OIDC identity provider configured
- **IAM Permissions**: Sufficient permissions to create IAM roles and policies
- **ArgoCD Namespace**: The target namespace must exist (default: `argocd`)

## 🛠️ Installation & Usage

### Quick Start

1. **Make the script executable**:

   ```bash
   chmod +x setup-argocd-ingress.sh
   ```

2. **Basic setup** (configuration only):

   ```bash
   ./setup-argocd-ingress.sh --domain argocd.yourdomain.com
   ```

3. **Full automated deployment**:

   ```bash
   ./setup-argocd-ingress.sh \
     --domain argocd.yourdomain.com \
     --repo-url https://github.com/yourusername/your-repo.git \
     --full-deploy
   ```

### Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `--domain DOMAIN` | ArgoCD domain name | `argocd.local` |
| `--repo-url URL` | GitHub repository URL | None |
| `--github-user USERNAME` | GitHub username for private repos | None |
| `--ingress-class CLASS` | Kubernetes ingress class | `alb` |
| `--namespace NAMESPACE` | ArgoCD namespace | `argocd` |
| `--apply-now` | Apply static manifests immediately | false |
| `--deploy-app` | Deploy ArgoCD application after creation | false |
| `--wait-for-sync` | Wait for ArgoCD application to sync | false |
| `--full-deploy` | Complete automated deployment | false |
| `--help` | Show help message | - |

### Usage Examples

#### Development Setup

```bash
# Basic development setup with local domain
./setup-argocd-ingress.sh \
  --domain argocd.local \
  --apply-now
```

#### Staging Environment

```bash
# Staging setup with GitHub integration
./setup-argocd-ingress.sh \
  --domain argocd-staging.yourdomain.com \
  --repo-url https://github.com/yourusername/your-repo.git \
  --github-user yourusername \
  --full-deploy
```

#### Production Deployment

```bash
# Production setup with custom namespace
./setup-argocd-ingress.sh \
  --domain argocd.yourdomain.com \
  --repo-url https://github.com/yourusername/your-repo.git \
  --github-user yourusername \
  --namespace argocd-prod \
  --full-deploy
```

## 📁 Generated File Structure

The script creates the following directory structure:

```bash
project-root/
├── deployments/argocd/
│   ├── kubernetes/
│   │   ├── ingress.yaml              # Static ingress manifest
│   │   └── server-config.yaml        # ArgoCD server configuration
│   └── helm/
│       ├── Chart.yaml                # Helm chart metadata
│       ├── values.yaml               # Default values (development)
│       ├── values-staging.yaml       # Staging environment values
│       ├── values-prod.yaml          # Production environment values
│       └── templates/
│           ├── ingress.yaml          # Ingress template
│           ├── server-config.yaml    # Server config template
│           └── _helpers.tpl          # Helm helper templates
└── argocd/applications/
    └── argocd-ingress-application.yaml # ArgoCD application manifest
```

## ⚙️ Configuration Details

### Environment-Specific Settings

#### Development (`values.yaml`)

- HTTP-only ingress
- Insecure ArgoCD server
- Local domain support

#### Staging (`values-staging.yaml`)

- HTTPS with staging domain
- TLS termination at ALB
- Enhanced security settings

#### Production (`values-prod.yaml`)

- Full HTTPS enforcement
- SSL certificate integration
- Production-grade security policies

### AWS Load Balancer Annotations

The script configures the following ALB annotations:

- `alb.ingress.kubernetes.io/scheme: internet-facing`
- `alb.ingress.kubernetes.io/target-type: ip`
- `alb.ingress.kubernetes.io/backend-protocol: HTTP`
- `alb.ingress.kubernetes.io/backend-protocol-version: GRPC`
- `alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'`
- `alb.ingress.kubernetes.io/ssl-redirect: "443"`

## 🔐 Authentication & Security

### ArgoCD Access

After successful deployment, access ArgoCD using:

- **URL**: `http://your-domain` or `https://your-domain`
- **Username**: `admin`
- **Password**: Retrieved automatically from `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo`

### GitHub Integration

For private repositories, the script:

1. Prompts for GitHub Personal Access Token (PAT)
2. Creates a Kubernetes secret with repository credentials
3. Labels the secret for ArgoCD repository management

### Security Considerations

- Uses TLS termination at the AWS Load Balancer level
- Supports both HTTP (development) and HTTPS (production) configurations
- Implements proper health checks and SSL policies
- Follows Kubernetes security best practices

## 🚦 Deployment Modes

### 1. Configuration Only (Default)

Creates all necessary files without applying them:

```bash
./setup-argocd-ingress.sh --domain your-domain.com
```

### 2. Apply Static Manifests

Creates files and applies static Kubernetes manifests:

```bash
./setup-argocd-ingress.sh --domain your-domain.com --apply-now
```

### 3. Deploy ArgoCD Application

Creates and deploys the ArgoCD application:

```bash
./setup-argocd-ingress.sh --domain your-domain.com --deploy-app
```

### 4. Full Automated Deployment

Complete end-to-end deployment with verification:

```bash
./setup-argocd-ingress.sh --domain your-domain.com --full-deploy
```

## 🔍 Verification & Troubleshooting

### Check Deployment Status

```bash
# Verify ArgoCD applications
kubectl get applications -n argocd

# Check ingress status
kubectl get ingress argocd-server-ingress -n argocd

# Monitor application sync
kubectl get application argocd-ingress -n argocd -w
```

### Common Issues & Solutions

#### 1. AWS Load Balancer Controller Not Installing

**Issue**: Helm installation fails with OIDC errors
**Solution**:

- Verify EKS cluster has OIDC provider configured
- Check IAM roles and policies are properly attached
- Ensure sufficient AWS permissions

#### 2. Ingress Not Getting External IP

**Issue**: ALB hostname shows as "Pending"
**Solution**:

- Check AWS Load Balancer Controller logs: `kubectl logs -n kube-system deployment/aws-load-balancer-controller`
- Verify subnet tags for ALB discovery
- Check security groups and VPC configuration

#### 3. ArgoCD Application Not Syncing

**Issue**: Application shows "OutOfSync" status
**Solution**:

- Verify GitHub repository URL and credentials
- Check ArgoCD has permissions to access the repository
- Manual sync: `kubectl patch application argocd-ingress -n argocd --type merge -p='{"operation":{"sync":{"syncStrategy":{"apply":{"force":true}}}}}'`

#### 4. Cannot Access ArgoCD UI

**Issue**: Domain not resolving or connection refused
**Solution**:

- Add DNS CNAME record pointing to ALB hostname
- For local testing, add entry to `/etc/hosts`
- Use port-forward as fallback: `kubectl port-forward svc/argocd-server -n argocd 8080:80`

### Useful Debug Commands

```bash
# Get ALB hostname
kubectl get ingress argocd-server-ingress -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Check ArgoCD server logs
kubectl logs deployment/argocd-server -n argocd

# Verify AWS Load Balancer Controller
kubectl get deployment aws-load-balancer-controller -n kube-system

# Check application details
kubectl describe application argocd-ingress -n argocd
```

## 🌐 DNS Configuration

### For Production Deployments

1. **Get ALB Hostname**:

   ```bash
   kubectl get ingress argocd-server-ingress -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
   ```

2. **Create DNS Record**:
   - Type: CNAME
   - Name: your-argocd-domain
   - Value: ALB hostname from step 1

### For Local Development

Add to `/etc/hosts` (get IP first with `nslookup <ALB_HOSTNAME>`):

```bash
<ALB_IP> argocd.local
```
