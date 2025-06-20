#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
ARGOCD_NAMESPACE="argocd"
INGRESS_CLASS="alb"
ARGOCD_DOMAIN="argocd.local"
GITHUB_REPO_URL=""
GITHUB_USERNAME=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEPLOY_APP=false
WAIT_FOR_SYNC=false
FULL_DEPLOY=false

# Function definitions
print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

validate_prerequisites() {
    print_status "Validating prerequisites..."
    
    if ! command_exists kubectl; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! command_exists helm; then
        print_error "helm is not installed or not in PATH"
        exit 1
    fi
    
    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    if ! kubectl get namespace $ARGOCD_NAMESPACE >/dev/null 2>&1; then
        print_error "ArgoCD namespace '$ARGOCD_NAMESPACE' does not exist"
        exit 1
    fi
    
    print_success "Prerequisites validated"
}

install_aws_load_balancer_controller() {
    print_status "Checking for AWS Load Balancer Controller..."
    
    if kubectl get deployment aws-load-balancer-controller -n kube-system >/dev/null 2>&1; then
        print_success "AWS Load Balancer Controller already exists"
        return
    fi
    
    print_status "Installing AWS Load Balancer Controller..."
    
    # Check if cluster has OIDC provider configured
    local cluster_name=$(kubectl config current-context | cut -d'/' -f2 2>/dev/null || echo "unknown")
    print_warning "Ensure your EKS cluster has an OIDC provider configured"
    print_warning "Cluster: $cluster_name"
    
    # Add EKS chart repository
    helm repo add eks https://aws.github.io/eks-charts
    helm repo update
    
    # Install AWS Load Balancer Controller
    # Note: This requires proper IAM roles and OIDC provider setup
    helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
        --set clusterName="$cluster_name" \
        --set serviceAccount.create=true \
        --set serviceAccount.name=aws-load-balancer-controller \
        --namespace kube-system \
        --wait || {
        print_error "Failed to install AWS Load Balancer Controller"
        print_error "Please ensure:"
        print_error "1. EKS cluster has OIDC provider configured"
        print_error "2. IAM role for service account is properly set up"
        print_error "3. AWS Load Balancer Controller IAM policy is attached"
        exit 1
    }
    
    print_success "AWS Load Balancer Controller installed"
}

create_argocd_static_manifests() {
    print_status "Creating ArgoCD static Kubernetes manifests..."
    
    # Create kubernetes directory for ArgoCD if it doesn't exist
    ARGOCD_K8S_DIR="$PROJECT_ROOT/deployments/argocd/kubernetes"
    mkdir -p "$ARGOCD_K8S_DIR"
    
    # Create ArgoCD ingress manifest
    cat > "$ARGOCD_K8S_DIR/ingress.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: $ARGOCD_NAMESPACE
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/backend-protocol-version: GRPC
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
    alb.ingress.kubernetes.io/healthcheck-protocol: HTTP
    alb.ingress.kubernetes.io/healthcheck-port: "8080"
    # For development/local - use HTTP. For production, configure SSL certificate
    # alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/cert-id
spec:
  ingressClassName: alb
  rules:
  - host: $ARGOCD_DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
EOF
    
    # Create ArgoCD server configuration patch
    cat > "$ARGOCD_K8S_DIR/server-config.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
  namespace: $ARGOCD_NAMESPACE
  labels:
    app.kubernetes.io/name: argocd-cmd-params-cm
    app.kubernetes.io/part-of: argocd
data:
  server.insecure: "true"
  server.grpc.web: "true"
EOF
    
    print_success "ArgoCD static manifests created in $ARGOCD_K8S_DIR"
}

create_argocd_helm_chart() {
    print_status "Creating ArgoCD Helm chart..."
    
    # Create helm directory for ArgoCD
    ARGOCD_HELM_DIR="$PROJECT_ROOT/deployments/argocd/helm"
    mkdir -p "$ARGOCD_HELM_DIR/templates"
    
    # Create Chart.yaml
    cat > "$ARGOCD_HELM_DIR/Chart.yaml" <<EOF
apiVersion: v2
name: argocd-ingress
description: ArgoCD Ingress and Configuration Helm Chart
type: application
version: 1.0.0
appVersion: "2.8.0"
keywords:
  - argocd
  - gitops
  - ingress
home: https://argoproj.github.io/argo-cd/
sources:
  - https://github.com/argoproj/argo-cd
maintainers:
  - name: Cloud Engineering Team
EOF
    
    # Create values.yaml
    cat > "$ARGOCD_HELM_DIR/values.yaml" <<EOF
# ArgoCD Ingress Configuration
ingress:
  enabled: true
  className: "alb"
  host: "$ARGOCD_DOMAIN"
  annotations:
    alb.ingress.kubernetes.io/scheme: "internet-facing"
    alb.ingress.kubernetes.io/target-type: "ip"
    alb.ingress.kubernetes.io/backend-protocol: "HTTP"
    alb.ingress.kubernetes.io/backend-protocol-version: "GRPC"
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/healthcheck-path: "/healthz"
    alb.ingress.kubernetes.io/healthcheck-protocol: "HTTP"
    alb.ingress.kubernetes.io/healthcheck-port: "8080"

# ArgoCD Server Configuration
server:
  insecure: true
  grpcWeb: true

# Namespace configuration
namespace: "$ARGOCD_NAMESPACE"

# Environment-specific overrides
environment: "development"
EOF
    
    # Create values-staging.yaml
    cat > "$ARGOCD_HELM_DIR/values-staging.yaml" <<EOF
# Staging environment overrides
environment: "staging"

ingress:
  host: "argocd-staging.local"
  
server:
  insecure: false  # Use TLS in staging
EOF
    
    # Create values-prod.yaml
    cat > "$ARGOCD_HELM_DIR/values-prod.yaml" <<EOF
# Production environment overrides
environment: "production"

ingress:
  host: "argocd.yourdomain.com"
  annotations:
    alb.ingress.kubernetes.io/scheme: "internet-facing"
    alb.ingress.kubernetes.io/target-type: "ip"
    alb.ingress.kubernetes.io/backend-protocol: "HTTP"
    alb.ingress.kubernetes.io/backend-protocol-version: "GRPC"
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS": 443}]'
    alb.ingress.kubernetes.io/certificate-arn: "arn:aws:acm:us-west-2:123456789012:certificate/your-cert-id"
    alb.ingress.kubernetes.io/ssl-policy: "ELBSecurityPolicy-TLS-1-2-2017-01"

server:
  insecure: false  # Always use TLS in production
EOF
    
    # Create ingress template
    cat > "$ARGOCD_HELM_DIR/templates/ingress.yaml" <<'EOF'
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: {{ .Values.namespace }}
  annotations:
    {{- range $key, $value := .Values.ingress.annotations }}
    {{ $key }}: {{ $value | quote }}
    {{- end }}
spec:
  ingressClassName: {{ .Values.ingress.className }}
  rules:
  - host: {{ .Values.ingress.host }}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
{{- end }}
EOF
    
    # Create server config template
    cat > "$ARGOCD_HELM_DIR/templates/server-config.yaml" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
  namespace: {{ .Values.namespace }}
  labels:
    app.kubernetes.io/name: argocd-cmd-params-cm
    app.kubernetes.io/part-of: argocd
data:
  {{- if .Values.server.insecure }}
  server.insecure: "true"
  {{- end }}
  {{- if .Values.server.grpcWeb }}
  server.grpc.web: "true"
  {{- end }}
EOF
    
    # Create helpers template
    cat > "$ARGOCD_HELM_DIR/templates/_helpers.tpl" <<'EOF'
{{/*
Expand the name of the chart.
*/}}
{{- define "argocd-ingress.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "argocd-ingress.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "argocd-ingress.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "argocd-ingress.labels" -}}
helm.sh/chart: {{ include "argocd-ingress.chart" . }}
{{ include "argocd-ingress.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "argocd-ingress.selectorLabels" -}}
app.kubernetes.io/name: {{ include "argocd-ingress.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
EOF
    
    print_success "ArgoCD Helm chart created in $ARGOCD_HELM_DIR"
}

update_argocd_applications() {
    print_status "Creating ArgoCD ingress application manifest..."
    
    # Create ArgoCD application for the ingress
    cat > "$PROJECT_ROOT/argocd/applications/argocd-ingress-application.yaml" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd-ingress
  namespace: $ARGOCD_NAMESPACE
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${GITHUB_REPO_URL:-'https://github.com/yourusername/your-repo.git'}
    targetRevision: HEAD
    path: deployments/argocd/helm
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: $ARGOCD_NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ApplyOutOfSyncOnly=true
EOF
    
    # Update app-of-apps.yaml to include the new application
    if [[ -f "$PROJECT_ROOT/argocd/app-of-apps.yaml" ]]; then
        print_status "Adding ArgoCD ingress application to app-of-apps..."
        
        # Check if argocd-ingress is already in app-of-apps
        if ! grep -q "argocd-ingress" "$PROJECT_ROOT/argocd/app-of-apps.yaml"; then
            # Add the new application to the sources list
            cat >> "$PROJECT_ROOT/argocd/app-of-apps.yaml" <<EOF
  - repoURL: ${GITHUB_REPO_URL:-'https://github.com/yourusername/your-repo.git'}
    targetRevision: HEAD
    path: argocd/applications
    directory:
      recurse: true
      include: 'argocd-ingress-application.yaml'
EOF
        fi
    fi
    
    print_success "ArgoCD application manifests updated"
}

apply_static_manifests() {
    print_status "Applying ArgoCD ingress configuration..."
    
    # Apply the static manifests directly
    kubectl apply -f "$PROJECT_ROOT/deployments/argocd/kubernetes/"
    
    # Restart ArgoCD server to apply configuration changes
    kubectl rollout restart deployment argocd-server -n $ARGOCD_NAMESPACE
    kubectl rollout status deployment argocd-server -n $ARGOCD_NAMESPACE --timeout=300s
    
    print_success "ArgoCD ingress configuration applied"
}

create_github_repo_connection() {
    if [[ -z "$GITHUB_REPO_URL" ]]; then
        print_warning "No GitHub repository URL provided, skipping repository setup"
        return
    fi
    
    print_status "Setting up GitHub repository connection..."
    
    # Create repository secret if username is provided (for private repos)
    if [[ -n "$GITHUB_USERNAME" ]]; then
        read -s -p "Enter your GitHub Personal Access Token (PAT): " GITHUB_TOKEN
        echo
        
        kubectl create secret generic github-repo-secret \
            --namespace=$ARGOCD_NAMESPACE \
            --from-literal=type=git \
            --from-literal=url="$GITHUB_REPO_URL" \
            --from-literal=username="$GITHUB_USERNAME" \
            --from-literal=password="$GITHUB_TOKEN" \
            --dry-run=client -o yaml | kubectl apply -f -
        
        kubectl label secret github-repo-secret -n $ARGOCD_NAMESPACE \
            argocd.argoproj.io/secret-type=repository
    fi
    
    print_success "GitHub repository connection configured"
}

get_argocd_credentials() {
    print_status "Retrieving ArgoCD admin credentials..."
    
    ARGOCD_PASSWORD=$(kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "Not found")
    
    if [[ "$ARGOCD_PASSWORD" == "Not found" ]]; then
        print_warning "Initial admin secret not found. ArgoCD may be using a different authentication method."
        ARGOCD_PASSWORD="Please check ArgoCD documentation for password retrieval"
    fi
    
    print_success "ArgoCD credentials retrieved"
}

# Add these functions to your script after get_argocd_credentials() function

deploy_argocd_application() {
    if [[ "$DEPLOY_APP" != "true" && "$FULL_DEPLOY" != "true" ]]; then
        print_status "Skipping application deployment (use --deploy-app or --full-deploy to auto-deploy)"
        return
    fi
    
    print_status "Deploying ArgoCD ingress application..."
    
    local app_file="$PROJECT_ROOT/argocd/applications/argocd-ingress-application.yaml"
    
    if [[ ! -f "$app_file" ]]; then
        print_error "ArgoCD application file not found: $app_file"
        exit 1
    fi
    
    # Apply the ArgoCD application
    kubectl apply -f "$app_file"
    
    if [[ "$WAIT_FOR_SYNC" == "true" || "$FULL_DEPLOY" == "true" ]]; then
        wait_for_application_sync
    fi
    
    print_success "ArgoCD application deployed"
}

wait_for_application_sync() {
    print_status "Waiting for ArgoCD application to sync..."
    
    local app_name="argocd-ingress"
    local max_wait=600  # 10 minutes
    local wait_time=0
    local check_interval=15
    
    while [[ $wait_time -lt $max_wait ]]; do
        # Check if application exists
        if ! kubectl get application "$app_name" -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
            print_status "Waiting for application to be created..."
            sleep $check_interval
            wait_time=$((wait_time + check_interval))
            continue
        fi
        
        # Get application status
        local sync_status=$(kubectl get application "$app_name" -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        local health_status=$(kubectl get application "$app_name" -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        
        print_status "App Status - Sync: $sync_status, Health: $health_status"
        
        # Check if application is synced and healthy
        if [[ "$sync_status" == "Synced" && "$health_status" == "Healthy" ]]; then
            print_success "✅ ArgoCD application synced and healthy!"
            return 0
        elif [[ "$sync_status" == "OutOfSync" ]]; then
            print_status "🔄 Triggering application sync..."
            kubectl patch application "$app_name" -n "$ARGOCD_NAMESPACE" \
                --type merge -p='{"operation":{"sync":{"syncStrategy":{"apply":{"force":true}}}}}' \
                2>/dev/null || true
        fi
        
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done
    
    print_warning "⚠️  Application sync timeout reached after $((max_wait/60)) minutes"
    print_warning "Check ArgoCD UI for detailed status: http://$ARGOCD_DOMAIN"
    return 1
}

verify_application_deployment() {
    if [[ "$DEPLOY_APP" != "true" && "$FULL_DEPLOY" != "true" ]]; then
        return
    fi
    
    print_status "Verifying ArgoCD application deployment..."
    
    local app_name="argocd-ingress"
    
    # Check if application exists and get its status
    if kubectl get application "$app_name" -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
        local sync_status=$(kubectl get application "$app_name" -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        local health_status=$(kubectl get application "$app_name" -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        
        echo "📱 ArgoCD Application Status:"
        echo "   Name: $app_name"
        echo "   Sync Status: $sync_status"
        echo "   Health Status: $health_status"
        
        if [[ "$sync_status" == "Synced" && "$health_status" == "Healthy" ]]; then
            print_success "✅ Application is synced and healthy"
        else
            print_warning "⚠️  Application needs attention - check ArgoCD UI"
        fi
    else
        print_warning "⚠️  ArgoCD application not found - manual deployment required"
    fi
}

display_setup_summary() {
    print_success "ArgoCD ingress setup completed!"
    echo
    echo "📁 Files Created:"
    echo "=================="
    echo "Static Manifests:"
    echo "  - deployments/argocd/kubernetes/ingress.yaml"
    echo "  - deployments/argocd/kubernetes/server-config.yaml"
    echo
    echo "Helm Chart:"
    echo "  - deployments/argocd/helm/Chart.yaml"
    echo "  - deployments/argocd/helm/values.yaml"
    echo "  - deployments/argocd/helm/values-staging.yaml"
    echo "  - deployments/argocd/helm/values-prod.yaml"
    echo "  - deployments/argocd/helm/templates/"
    echo
    echo "ArgoCD Applications:"
    echo "  - argocd/applications/argocd-ingress-application.yaml"
    echo
    
    # Show deployment status
    if [[ "$DEPLOY_APP" == "true" || "$FULL_DEPLOY" == "true" ]]; then
        echo "🚀 Deployment Status:"
        echo "===================="
        verify_application_deployment
        echo
    fi
    
    echo "🌐 Connection Information:"
    echo "=========================="
    echo "ArgoCD URL: http://$ARGOCD_DOMAIN"
    echo "Username: admin"
    echo "Password: $ARGOCD_PASSWORD"
    echo
    
    # Get ingress IP
    INGRESS_IP=$(kubectl get ingress argocd-server-ingress -n $ARGOCD_NAMESPACE \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Pending")
    
    if [[ "$INGRESS_IP" != "Pending" && -n "$INGRESS_IP" ]]; then
        echo "🔧 DNS Configuration:"
        echo "====================="
        echo "Create a CNAME record pointing $ARGOCD_DOMAIN to:"
        echo "$INGRESS_IP"
        echo
        echo "Or add this to your /etc/hosts file (get IP with: nslookup $INGRESS_IP):"
        echo "# First resolve ALB hostname to IP, then add:"
        echo "# <ALB_IP> $ARGOCD_DOMAIN"
        echo
    else
        echo "⚠️  ALB hostname is pending. Check with:"
        echo "   kubectl get ingress argocd-server-ingress -n $ARGOCD_NAMESPACE"
        echo
    fi
    
    echo "🚀 Next Steps:"
    echo "=============="
    if [[ "$DEPLOY_APP" != "true" && "$FULL_DEPLOY" != "true" ]]; then
        echo "1. Deploy the ArgoCD application:"
        echo "   kubectl apply -f argocd/applications/argocd-ingress-application.yaml"
        echo "2. Configure DNS or add hosts entry"
        echo "3. Access ArgoCD UI at http://$ARGOCD_DOMAIN"
    else
        echo "1. Configure DNS or add hosts entry (if needed)"
        echo "2. Access ArgoCD UI at http://$ARGOCD_DOMAIN"
        echo "3. Verify all applications are syncing properly"
    fi
    echo "4. Set up your main API and auxiliary service applications"
    echo "5. Configure GitHub Actions for CI/CD"
    echo
    echo "📋 Useful Commands:"
    echo "==================="
    echo "# Check ArgoCD applications"
    echo "kubectl get applications -n $ARGOCD_NAMESPACE"
    echo
    echo "# Watch application sync status"
    echo "kubectl get application argocd-ingress -n $ARGOCD_NAMESPACE -w"
    echo
    echo "# Port-forward ArgoCD (if ingress not working)"
    echo "kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:80"
    echo
    echo "# Trigger manual sync"
    echo "kubectl patch application argocd-ingress -n $ARGOCD_NAMESPACE --type merge -p='{\"operation\":{\"sync\":{\"syncStrategy\":{\"apply\":{\"force\":true}}}}}'"
}

main() {
    echo "=========================================="
    echo "🚀 ArgoCD Ingress Setup for Kantox Challenge"
    echo "=========================================="
    echo
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --domain)
                ARGOCD_DOMAIN="$2"
                shift 2
                ;;
            --repo-url)
                GITHUB_REPO_URL="$2"
                shift 2
                ;;
            --github-user)
                GITHUB_USERNAME="$2"
                shift 2
                ;;
            --ingress-class)
                INGRESS_CLASS="$2"
                shift 2
                ;;
            --namespace)
                ARGOCD_NAMESPACE="$2"
                shift 2
                ;;
            --apply-now)
                APPLY_NOW=true
                shift
                ;;
            --deploy-app)
                DEPLOY_APP=true
                shift
                ;;
            --wait-for-sync)
                WAIT_FOR_SYNC=true
                shift
                ;;
            --full-deploy)
                FULL_DEPLOY=true
                APPLY_NOW=true
                DEPLOY_APP=true
                WAIT_FOR_SYNC=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --domain DOMAIN          ArgoCD domain (default: argocd.local)"
                echo "  --repo-url URL           GitHub repository URL"
                echo "  --github-user USERNAME   GitHub username (for private repos)"
                echo "  --ingress-class CLASS    Ingress class (default: alb)"
                echo "  --namespace NAMESPACE    ArgoCD namespace (default: argocd)"
                echo "  --apply-now              Apply static manifests immediately"
                echo "  --deploy-app             Deploy ArgoCD application after creation"
                echo "  --wait-for-sync          Wait for ArgoCD application to sync"
                echo "  --full-deploy            Complete deployment (apply + deploy + wait)"
                echo "  --help                   Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    validate_prerequisites
    install_aws_load_balancer_controller
    create_argocd_static_manifests
    create_argocd_helm_chart
    create_github_repo_connection
    get_argocd_credentials
    update_argocd_applications
    
    if [[ "$APPLY_NOW" == "true" ]]; then
        apply_static_manifests
    fi
    
    # Deploy ArgoCD application if requested
    deploy_argocd_application
    
    # Verify deployment if app was deployed
    verify_application_deployment
    
    display_setup_summary
}

main "$@"