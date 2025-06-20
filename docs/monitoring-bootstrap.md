# Enhanced Monitoring Stack Bootstrap Script

Bash script for deploying a complete monitoring stack on Kubernetes using Prometheus, Grafana, and Alertmanager. This script automates the setup of monitoring infrastructure with configurable access controls and service integration.

## 🚀 Features

- **Complete Monitoring Stack**: Deploys Prometheus, Grafana, Alertmanager, Node Exporter, and Kube State Metrics
- **Flexible Access Control**: Supports public, office-only, and internal access modes
- **Service Integration**: Automatically configures monitoring for main API and auxiliary services
- **Secure Configuration**: Generates secure passwords and creates proper secrets
- **Output Modes**: Can apply directly to cluster, generate files, or both
- **AWS Integration**: Supports AWS Load Balancer Controller with SSL certificates

## 📋 Prerequisites

### Required Tools

- `kubectl` - Kubernetes command-line tool
- `helm` - Kubernetes package manager
- `openssl` - For password generation
- `curl` - For IP detection (office-only mode)
- `python3` - For path resolution

### Required Access

- Kubernetes cluster access with admin privileges
- AWS ACM certificate (for SSL/TLS)
- Appropriate IAM permissions for ALB creation

## 🛠️ Installation

1. **Download the script**:

   ```bash
   curl -O https://your-repo.com/monitoring-bootstrap.sh
   chmod +x monitoring-bootstrap.sh
   ```

2. **Verify prerequisites**:

   ```bash
   kubectl cluster-info
   helm version
   ```

## 📖 Usage

### Basic Usage

```bash
./monitoring-bootstrap.sh --domain monitoring.company.com --cert-arn arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012
```

### Advanced Usage Examples

**Office-only access with custom IP**:

```bash
./monitoring-bootstrap.sh \
  --domain monitoring.company.com \
  --cert-arn arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012 \
  --access office-only \
  --office-ip 203.0.113.0/24
```

**Generate configuration files only**:

```bash
./monitoring-bootstrap.sh \
  --domain monitoring.company.com \
  --cert-arn arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012 \
  --output files
```

**Internal VPC access**:

```bash
./monitoring-bootstrap.sh \
  --domain monitoring.internal.company.com \
  --cert-arn arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012 \
  --access internal
```

## ⚙️ Configuration Options

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `--domain` | Domain name for monitoring dashboard | `monitoring.company.com` |
| `--cert-arn` | AWS ACM certificate ARN | `arn:aws:acm:us-east-1:123456789012:certificate/...` |

### Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--namespace` | `monitoring` | Kubernetes namespace for monitoring stack |
| `--access` | `public` | Access type: `public`, `office-only`, `internal` |
| `--output` | `both` | Output mode: `apply`, `files`, `both` |
| `--office-ip` | Auto-detect | IP/CIDR for office-only access |
| `--skip-services` | - | Skip application service installation |

### Environment Variables

You can also configure the script using environment variables:

```bash
export DOMAIN="monitoring.company.com"
export CERTIFICATE_ARN="arn:aws:acm:..."
export NAMESPACE="monitoring"
export ACCESS_TYPE="office-only"
export OUTPUT_MODE="both"
export OFFICE_IP="203.0.113.0/24"
```

## 🏗️ Architecture

The script deploys the following components:

### Monitoring Stack

- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **Alertmanager**: Alert routing and management
- **Node Exporter**: Host metrics collection
- **Kube State Metrics**: Kubernetes cluster metrics

### Networking

- **AWS Load Balancer**: Internet-facing or internal ALB
- **SSL/TLS**: Automatic certificate management
- **Access Control**: IP-based restrictions

### Storage

- **Prometheus**: 20GB persistent storage, 30-day retention
- **Grafana**: 10GB persistent storage for dashboards

## 🔐 Access Control Modes

### Public Access

- **Description**: Accessible from anywhere on the internet
- **Use Case**: Public monitoring dashboards
- **Security**: ⚠️ Requires strong authentication

### Office-Only Access

- **Description**: Restricted to specific IP addresses
- **Use Case**: Corporate monitoring access
- **Auto-detection**: Automatically detects your public IP
- **Manual override**: Use `--office-ip` for custom ranges

### Internal Access

- **Description**: VPC-only access via internal load balancer
- **Use Case**: Internal infrastructure monitoring
- **IP Ranges**: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`

## 📁 Output Structure

When using `--output files` or `--output both`, the script generates:

```bash
deployments/monitoring/
├── helm/
│   └── values.yaml          # Helm values for monitoring stack
└── k8s/
    ├── ingress.yaml         # Load balancer configuration
    └── servicemonitors.yaml # Service monitoring configuration
```

## 🔧 Service Integration

The script automatically configures monitoring for:

- **Main API Service**: Located at `./deployments/main-api/helm`
- **Auxiliary Service**: Located at `./deployments/auxiliary-service`

### Service Configuration

| Service | Namespace | Values File |
|---------|-----------|-------------|
| Main API | `main-api` | `values-staging.yaml` |
| Auxiliary Service | `auxiliary-service` | `values-staging.yaml` |

### Custom Service Paths

Override default paths using environment variables:

```bash
export MAIN_API_CHART_PATH="./custom/main-api/chart"
export AUXILIARY_SERVICE_CHART_PATH="./custom/auxiliary-service"
export MAIN_API_VALUES="./custom/main-api/values.yaml"
export AUXILIARY_SERVICE_VALUES="./custom/auxiliary-service/values.yaml"
```

## 🚨 Troubleshooting

### Common Issues

1. **Certificate ARN not found**

```bash
# Verify certificate exists
aws acm list-certificates --region us-east-1
```

2.**Kubectl connection failed**:

```bash
# Check cluster connection
kubectl cluster-info
aws eks update-kubeconfig --region us-east-1 --name your-cluster
```

3.**Helm repository issues**

```bash
# Update repositories manually
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

4.**ServiceMonitor CRDs not ready**

```bash
# Apply ServiceMonitors manually
kubectl apply -f deployments/monitoring/k8s/servicemonitors.yaml
```

### Debug Commands

```bash
# Check deployment status
kubectl get pods -n monitoring
kubectl get servicemonitors -n monitoring
kubectl describe ingress monitoring-ingress -n monitoring

# View logs
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus
```

## 🔑 Security Credentials

After successful deployment, save these credentials securely:

- **Grafana Username**: `admin`
- **Grafana Password**: Generated during deployment (displayed in terminal)
- **Dashboard URL**: `https://your-domain.com`

## 📝 Customization

### Custom Grafana Configuration

Edit the generated `values.yaml` file to customize:

- Dashboard settings
- Data source connections
- User authentication
- Notification channels

### Custom Prometheus Configuration

Modify retention, storage, and scraping settings:

```yaml
prometheus:
  prometheusSpec:
    retention: 60d
    retentionSize: 50GB
    scrapeInterval: 15s
```
