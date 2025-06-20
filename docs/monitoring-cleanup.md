# Monitoring Stack Cleanup Script

A bash script for safely removing monitoring infrastructure deployed via the bootstrap script. This cleanup script mirrors the bootstrap deployment process to ensure complete and safe removal of all monitoring components.

## 🚨 Important Safety Notice

This script can **permanently delete monitoring data**. Always run with `--dry-run` first to preview changes.

## 📋 Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Cleanup Modes](#cleanup-modes)
- [Configuration](#configuration)
- [Examples](#examples)
- [Safety Features](#safety-features)
- [Troubleshooting](#troubleshooting)

## Features

- **Three cleanup modes**: Selective (safe), Complete (removes data), Files-only
- **Dry-run capability**: Preview changes before execution
- **Interactive confirmations**: Prevents accidental deletions
- **Bootstrap compatibility**: Matches the original deployment structure
- **Service cleanup**: Removes main-api and auxiliary services
- **Comprehensive logging**: Colored output with timestamps
- **Error handling**: Graceful handling of missing resources

## Prerequisites

### For Cluster Operations

- `kubectl` - Kubernetes command-line tool
- `helm` - Helm package manager
- Active Kubernetes cluster connection
- Appropriate RBAC permissions

### For Files-Only Mode

- Basic bash environment (no additional tools required)

## Installation

1. **Download the script:**

   ```bash
   curl -O https://your-repo/monitoring-cleanup.sh
   chmod +x monitoring-cleanup.sh
   ```

2. **Verify prerequisites:**

   ```bash
   kubectl cluster-info
   helm version
   ```

## Usage

### Basic Syntax

```bash
./monitoring-cleanup.sh --domain <DOMAIN> [OPTIONS]
```

### Required Parameters

- `--domain DOMAIN` - Domain used in deployment (required for safety validation)

### Optional Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--namespace NAMESPACE` | Monitoring namespace | `monitoring` |
| `--mode MODE` | Cleanup mode (selective/complete/files-only) | `selective` |
| `--force` | Skip confirmation prompts | `false` |
| `--dry-run` | Show what would be deleted without executing | `false` |
| `--skip-services` | Don't clean up main-api/auxiliary-service | `false` |
| `-h, --help` | Show help message | - |

## Cleanup Modes

### 1. Selective Mode (Default - Safest)

```bash
./monitoring-cleanup.sh --domain monitoring.company.com
```

**Removes:**

- Monitoring stack (Prometheus, Grafana, AlertManager)
- ServiceMonitors
- Ingress configurations
- Generated files

**Preserves:**

- Persistent Volume Claims (monitoring data)
- Secrets (can be reused)

### 2. Complete Mode (⚠️ Dangerous)

```bash
./monitoring-cleanup.sh --domain monitoring.company.com --mode complete
```

**Removes everything including:**

- All selective mode items
- **Persistent Volume Claims (ALL DATA LOST)**
- Secrets
- Monitoring history

### 3. Files-Only Mode

```bash
./monitoring-cleanup.sh --mode files-only
```

**Removes only:**

- Generated Kubernetes YAML files
- Generated Helm configuration files
- Does not require cluster access

## Configuration

### Environment Variables

```bash
# Core Configuration
export DOMAIN="monitoring.company.com"
export NAMESPACE="monitoring"
export CLEANUP_MODE="selective"

# Service Configuration
export MAIN_API_NAMESPACE="main-api"
export AUXILIARY_SERVICE_NAMESPACE="auxiliary-service"
export CLEANUP_SERVICES="true"

# Behavior
export FORCE_DELETE="false"
export DRY_RUN="false"

# Paths (auto-detected relative to script)
export KUBERNETES_OUTPUT_PATH="../deployments/monitoring/k8s"
export HELM_OUTPUT_PATH="../deployments/monitoring/helm"
```

## Examples

### Preview Changes (Recommended First Step)

```bash
./monitoring-cleanup.sh --domain monitoring.company.com --dry-run
```

### Safe Cleanup

```bash
./monitoring-cleanup.sh --domain monitoring.company.com
```

### Complete Cleanup (Data Loss!)

```bash
./monitoring-cleanup.sh --domain monitoring.company.com --mode complete --force
```

### Clean Only Generated Files

```bash
./monitoring-cleanup.sh --mode files-only
```

### Custom Namespace

```bash
./monitoring-cleanup.sh --domain monitoring.company.com --namespace my-monitoring
```

### Skip Service Cleanup

```bash
./monitoring-cleanup.sh --domain monitoring.company.com --skip-services
```

## Safety Features

### 1. Domain Validation

- Requires domain parameter for cluster operations
- Prevents accidental execution on wrong environment

### 2. Interactive Confirmations

- Prompts before destructive operations
- Shows exactly what will be removed
- Can be bypassed with `--force` for automation

### 3. Dry Run Mode

```bash
./monitoring-cleanup.sh --domain monitoring.company.com --dry-run
```

- Shows all commands that would be executed
- No actual changes made
- Perfect for validation

### 4. Resource Detection

- Checks for existing resources before cleanup
- Exits gracefully if nothing to clean
- Lists found resources for confirmation

### 5. Error Handling

- Continues execution if resources already deleted
- Graceful handling of missing components
- Clear error messages with exit codes

## What Gets Cleaned Up

### Monitoring Stack Components

- **Helm Releases:**
  - `prometheus` (main monitoring stack)
  - `main-api` (if enabled)
  - `auxiliary-service` (if enabled)

- **Kubernetes Resources:**
  - Ingress: `monitoring-ingress`
  - ServiceMonitors: `main-api-monitor`, `auxiliary-service-monitor`
  - Secrets: `grafana-admin-secret` (complete mode only)
  - PVCs: All monitoring data (complete mode only)

- **Generated Files:**
  - `../deployments/monitoring/k8s/` - Kubernetes YAML files
  - `../deployments/monitoring/helm/` - Helm configuration files

## Troubleshooting

### Common Issues

#### 1. "Cannot connect to cluster"

```bash
kubectl cluster-info
# Ensure your kubeconfig is properly configured
```

#### 2. "kubectl not installed"

```bash
# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
```

#### 3. "helm not installed"

```bash
# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

#### 4. "Permission denied"

```bash
chmod +x monitoring-cleanup.sh
```

### Verification Commands

After cleanup, verify removal:

```bash
# Check Helm releases
helm list -n monitoring
helm list -n main-api
helm list -n auxiliary-service

# Check Kubernetes resources
kubectl get all -n monitoring

# Check files
ls -la ../deployments/monitoring/
```

### Recovery Options

If you need to restore after accidental deletion:

1. **Files Only:** Re-run the bootstrap script
2. **With Data Loss:** Restore from backups (if available)
3. **Partial Cleanup:** Individual component restoration possible

## Logging

The script provides comprehensive logging with color-coded output:

- 🟢 **Green:** Successful operations
- 🟡 **Yellow:** Warnings
- 🔴 **Red:** Errors
- 🔵 **Blue:** Information
- 🟦 **Cyan:** Dry-run operations

---

**💡 Pro Tip:** Always run `--dry-run` first to see exactly what will be removed!
