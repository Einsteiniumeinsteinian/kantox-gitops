#!/bin/bash

# =============================================================================
# Enhanced Monitoring Stack Bootstrap Script - Cleaned Up
# Supports dynamic parameters, organized file output, and service installation
# =============================================================================

set -e # Exit on any error

# Default Configuration
DOMAIN="${DOMAIN:-}"
NAMESPACE="${NAMESPACE:-monitoring}"
OFFICE_IP="${OFFICE_IP:-0.0.0.0/0}"
CERTIFICATE_ARN="${CERTIFICATE_ARN:-}"
ACCESS_TYPE="${ACCESS_TYPE:-public}" # Options: "public", "internal", "office-only"
OUTPUT_MODE="${OUTPUT_MODE:-both}"   # Options: "apply", "files", "both"

# Service Configuration
MAIN_API_CHART_PATH="${MAIN_API_CHART_PATH:-./deployments/main-api/helm}"
AUXILIARY_SERVICE_CHART_PATH="${AUXILIARY_SERVICE_CHART_PATH:-./deployments/auxiliary-service}"
MAIN_API_VALUES="${MAIN_API_VALUES:-./deployments/main-api/helm/values-staging.yaml}"
AUXILIARY_SERVICE_VALUES="${AUXILIARY_SERVICE_VALUES:-./deployments/auxiliary-service/values-staging.yaml}"
MAIN_API_NAMESPACE="${MAIN_API_NAMESPACE:-main-api}"
AUXILIARY_SERVICE_NAMESPACE="${AUXILIARY_SERVICE_NAMESPACE:-auxiliary-service}"
INSTALL_SERVICES="${INSTALL_SERVICES:-true}"

# Output paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBERNETES_OUTPUT_PATH="${KUBERNETES_OUTPUT_PATH:-${SCRIPT_DIR}/../deployments/monitoring/k8s}"
HELM_OUTPUT_PATH="${HELM_OUTPUT_PATH:-${SCRIPT_DIR}/../deployments/monitoring/helm}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARNING] $1${NC}"; }
error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Show help
show_help() {
    cat <<EOF
Enhanced Monitoring Stack Bootstrap Script

USAGE: $0 [OPTIONS]

REQUIRED:
    --domain DOMAIN             Domain for monitoring
    --cert-arn ARN             AWS ACM certificate ARN

OPTIONS:
    --namespace NAMESPACE       Monitoring namespace (default: monitoring)
    --access TYPE              Access type: public, office-only, internal (default: public)
    --output MODE              Output mode: apply, files, both (default: both)
    --office-ip IP             Office IP for office-only access
    --skip-services            Skip service installation
    -h, --help                 Show this help

EXAMPLES:
    # Basic deployment
    $0 --domain monitoring.company.com --cert-arn arn:aws:acm:...
    
    # Office-only access
    $0 --domain monitoring.company.com --cert-arn arn:aws:acm:... --access office-only
    
    # Generate files only
    $0 --domain monitoring.company.com --cert-arn arn:aws:acm:... --output files
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --cert-arn)
            CERTIFICATE_ARN="$2"
            shift 2
            ;;
        --access)
            ACCESS_TYPE="$2"
            shift 2
            ;;
        --output)
            OUTPUT_MODE="$2"
            shift 2
            ;;
        --office-ip)
            OFFICE_IP="$2"
            shift 2
            ;;
        --skip-services)
            INSTALL_SERVICES="false"
            shift
            ;;
        -h | --help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
        esac
    done
}

# Validate configuration
validate_config() {
    log "Validating configuration..."

    [[ -z "$DOMAIN" ]] && error "Missing required parameter: DOMAIN"
    [[ -z "$CERTIFICATE_ARN" ]] && error "Missing required parameter: CERTIFICATE_ARN"

    case $ACCESS_TYPE in
    "public" | "office-only" | "internal") ;;
    *) error "Invalid ACCESS_TYPE: $ACCESS_TYPE" ;;
    esac

    case $OUTPUT_MODE in
    "apply" | "files" | "both") ;;
    *) error "Invalid OUTPUT_MODE: $OUTPUT_MODE" ;;
    esac

    # Validate service paths if installing
    if [[ "$INSTALL_SERVICES" == "true" && ("$OUTPUT_MODE" == "apply" || "$OUTPUT_MODE" == "both") ]]; then
        [[ ! -d "$MAIN_API_CHART_PATH" ]] && error "Main API chart not found: $MAIN_API_CHART_PATH"
        [[ ! -d "$AUXILIARY_SERVICE_CHART_PATH" ]] && error "Auxiliary service chart not found: $AUXILIARY_SERVICE_CHART_PATH"
        [[ ! -f "$MAIN_API_VALUES" ]] && error "Main API values not found: $MAIN_API_VALUES"
        [[ ! -f "$AUXILIARY_SERVICE_VALUES" ]] && error "Auxiliary service values not found: $AUXILIARY_SERVICE_VALUES"
    fi

    log "✅ Configuration validated"
}

# Create output directories
create_output_directories() {
    if [[ "$OUTPUT_MODE" == "files" || "$OUTPUT_MODE" == "both" ]]; then
        log "Creating output directories..."

        KUBERNETES_OUTPUT_PATH=$(python3 -c "import os; print(os.path.abspath('$KUBERNETES_OUTPUT_PATH'))")
        HELM_OUTPUT_PATH=$(python3 -c "import os; print(os.path.abspath('$HELM_OUTPUT_PATH'))")

        mkdir -p "$KUBERNETES_OUTPUT_PATH" "$HELM_OUTPUT_PATH" || error "Failed to create output directories"

        log "✅ Output directories ready"
    fi
}

# Configure access settings
configure_access() {
    log "Configuring access settings..."

    case $ACCESS_TYPE in
    "public")
        OFFICE_IP="0.0.0.0/0"
        ALB_SCHEME="internet-facing"
        warn "⚠️  PUBLIC ACCESS: Monitoring accessible from anywhere!"
        ;;
    "office-only")
        if [[ "$OFFICE_IP" == "0.0.0.0/0" || -z "$OFFICE_IP" ]]; then
            DETECTED_IP=$(curl -s ifconfig.me 2>/dev/null || echo "")
            [[ -n "$DETECTED_IP" ]] && OFFICE_IP="${DETECTED_IP}/32" || error "Could not detect IP. Use --office-ip YOUR_IP"
        fi
        ALB_SCHEME="internet-facing"
        log "🔒 Office-only access: $OFFICE_IP"
        ;;
    "internal")
        OFFICE_IP="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
        ALB_SCHEME="internal"
        log "🔒 Internal access: VPC only"
        ;;
    esac

    log "✅ Access configured"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    command -v kubectl >/dev/null 2>&1 || error "kubectl not installed"
    command -v openssl >/dev/null 2>&1 || error "openssl not installed"

    if [[ "$OUTPUT_MODE" == "apply" || "$OUTPUT_MODE" == "both" ]]; then
        command -v helm >/dev/null 2>&1 || error "helm not installed"
        kubectl cluster-info >/dev/null 2>&1 || error "Cannot connect to cluster"
    fi

    log "✅ Prerequisites met"
}

# Setup Helm repositories
setup_helm_repos() {
    if [[ "$OUTPUT_MODE" == "apply" || "$OUTPUT_MODE" == "both" ]]; then
        log "Setting up Helm repositories..."

        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
        helm repo update >/dev/null 2>&1

        log "✅ Helm repositories ready"
    fi
}

# Create namespaces
create_namespaces() {
    if [[ "$OUTPUT_MODE" == "apply" || "$OUTPUT_MODE" == "both" ]]; then
        log "Creating namespaces..."

        kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f - >/dev/null

        if [[ "$INSTALL_SERVICES" == "true" ]]; then
            kubectl create namespace ${MAIN_API_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f - >/dev/null
            kubectl create namespace ${AUXILIARY_SERVICE_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f - >/dev/null
        fi

        log "✅ Namespaces ready"
    fi
}

# Install services (simplified)
install_services() {
    if [[ "$INSTALL_SERVICES" == "true" && ("$OUTPUT_MODE" == "apply" || "$OUTPUT_MODE" == "both") ]]; then
        log "Installing application services..."

        # Validate first
        if ! helm lint "$MAIN_API_CHART_PATH" -f "$MAIN_API_VALUES" >/dev/null 2>&1; then
            warn "Main API validation failed. Run: helm lint $MAIN_API_CHART_PATH -f $MAIN_API_VALUES"
            return 1
        fi

        if ! helm lint "$AUXILIARY_SERVICE_CHART_PATH" -f "$AUXILIARY_SERVICE_VALUES" >/dev/null 2>&1; then
            warn "Auxiliary service validation failed. Run: helm lint $AUXILIARY_SERVICE_CHART_PATH -f $AUXILIARY_SERVICE_VALUES"
            return 1
        fi

        helm upgrade --install auxiliary-service "$AUXILIARY_SERVICE_CHART_PATH" \
            -f "$AUXILIARY_SERVICE_VALUES" \
            --namespace "$AUXILIARY_SERVICE_NAMESPACE" \
            --wait --timeout 5m

        # Install services
        helm upgrade --install main-api "$MAIN_API_CHART_PATH" \
            -f "$MAIN_API_VALUES" \
            --namespace "$MAIN_API_NAMESPACE" \
            --wait --timeout 5m

        log "✅ Services installed"
    fi
}

# Generate secure passwords (simplified)
generate_passwords() {
    log "Generating secure passwords..."

    GRAFANA_PASSWORD=$(openssl rand -base64 32)

    log "✅ Passwords generated"
    echo -e "${BLUE}Grafana Password: ${GRAFANA_PASSWORD}${NC}"
    warn "🔐 SAVE THIS PASSWORD SECURELY!"
    echo ""
}

# Create secrets
create_secrets() {
    if [[ "$OUTPUT_MODE" == "apply" || "$OUTPUT_MODE" == "both" ]]; then
        log "Creating secrets..."

        kubectl create secret generic grafana-admin-secret \
            --from-literal=admin-user=admin \
            --from-literal=admin-password="${GRAFANA_PASSWORD}" \
            --namespace ${NAMESPACE} \
            --dry-run=client -o yaml | kubectl apply -f - >/dev/null

        log "✅ Secrets created"
    fi
}

# Generate Helm values (simplified)
generate_helm_values() {
    cat <<EOF
# Monitoring Stack Configuration - Generated $(date)
global:
  rbac:
    create: true

grafana:
  enabled: true
  admin:
    existingSecret: "grafana-admin-secret"
    userKey: "admin-user"
    passwordKey: "admin-password"
  grafana.ini:
    server:
      domain: ${DOMAIN}
      root_url: "https://${DOMAIN}"
  persistence:
    enabled: true
    storageClassName: gp2
    size: 10Gi
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
      - name: Prometheus
        type: prometheus
        url: http://prometheus-kube-prometheus-prometheus:9090

prometheus:
  enabled: true
  prometheusSpec:
    retention: 30d
    retentionSize: 10GB
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp2
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 20Gi
    serviceMonitorSelectorNilUsesHelmValues: false

alertmanager:
  enabled: true

nodeExporter:
  enabled: true

kubeStateMetrics:
  enabled: true

prometheusOperator:
  enabled: true
EOF
}

# Generate ingress
generate_ingress_content() {
    cat <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: monitoring-ingress
  namespace: ${NAMESPACE}
  annotations:
    alb.ingress.kubernetes.io/scheme: ${ALB_SCHEME}
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/certificate-arn: "${CERTIFICATE_ARN}"
    alb.ingress.kubernetes.io/inbound-cidrs: "${OFFICE_IP}"
spec:
  ingressClassName: alb
  rules:
  - host: ${DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: prometheus-grafana
            port:
              number: 80
EOF
}

# Generate ServiceMonitors
generate_servicemonitor_content() {
    cat <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: main-api-monitor
  namespace: ${NAMESPACE}
  labels:
    app: main-api
    release: prometheus
spec:
  selector:
    matchLabels:
      app: main-api
  namespaceSelector:
    matchNames:
    - ${MAIN_API_NAMESPACE}
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: auxiliary-service-monitor
  namespace: ${NAMESPACE}
  labels:
    app: auxiliary-service
    release: prometheus
spec:
  selector:
    matchLabels:
      app: auxiliary-service
  namespaceSelector:
    matchNames:
    - ${AUXILIARY_SERVICE_NAMESPACE}
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
EOF
}

# Create monitoring configurations
create_monitoring_configs() {
    log "Creating monitoring configurations..."

    if [[ "$OUTPUT_MODE" == "files" || "$OUTPUT_MODE" == "both" ]]; then
        generate_helm_values >"${HELM_OUTPUT_PATH}/values.yaml"
        generate_ingress_content >"${KUBERNETES_OUTPUT_PATH}/ingress.yaml"
        generate_servicemonitor_content >"${KUBERNETES_OUTPUT_PATH}/servicemonitors.yaml"
        log "📄 Generated configuration files"
    fi

    log "✅ Configurations ready"
}

# Install monitoring stack
install_monitoring_stack() {
    if [[ "$OUTPUT_MODE" == "apply" || "$OUTPUT_MODE" == "both" ]]; then
        log "Installing monitoring stack..."

        VALUES_FILE="${HELM_OUTPUT_PATH}/values.yaml"
        if [[ "$OUTPUT_MODE" == "apply" ]]; then
            VALUES_FILE="/tmp/monitoring-values-${RANDOM}.yaml"
            generate_helm_values >"$VALUES_FILE"
        fi

        helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
            --namespace ${NAMESPACE} \
            --values "$VALUES_FILE" \
            --wait --timeout 10m \
            --set prometheus.prometheusSpec.maximumStartupDurationSeconds=600

        [[ "$OUTPUT_MODE" == "apply" ]] && rm -f "$VALUES_FILE"

        log "✅ Monitoring stack installed"
    fi
}

# Wait for CRDs (simplified)
wait_for_crds() {
    if [[ "$OUTPUT_MODE" == "apply" || "$OUTPUT_MODE" == "both" ]]; then
        log "Waiting for ServiceMonitor CRDs..."

        local attempts=0
        while [ $attempts -lt 30 ]; do
            if kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
                if kubectl get servicemonitors -n ${NAMESPACE} >/dev/null 2>&1; then
                    log "✅ ServiceMonitor CRDs ready"
                    return 0
                fi
            fi
            sleep 10
            ((attempts++))
        done

        warn "ServiceMonitor CRDs not ready. Apply manually later: kubectl apply -f ${KUBERNETES_OUTPUT_PATH}/servicemonitors.yaml"
        return 1
    fi
}

# Apply ServiceMonitors
apply_servicemonitors() {
    if [[ "$OUTPUT_MODE" == "apply" || "$OUTPUT_MODE" == "both" ]]; then
        if wait_for_crds; then
            generate_servicemonitor_content | kubectl apply -f -
            generate_ingress_content | kubectl apply -f -
            log "✅ ServiceMonitors and ingress applied"
        fi
    fi
}

# Print final information
print_final_info() {
    echo ""
    echo "🎉 DEPLOYMENT COMPLETE! 🎉"
    echo "=========================="

    if [[ "$OUTPUT_MODE" == "apply" || "$OUTPUT_MODE" == "both" ]]; then
        echo -e "${BLUE}📊 Grafana: https://${DOMAIN}${NC}"
        echo -e "${BLUE}   Username: admin${NC}"
        echo -e "${BLUE}   Password: ${GRAFANA_PASSWORD}${NC}"
    fi

    if [[ "$OUTPUT_MODE" == "files" || "$OUTPUT_MODE" == "both" ]]; then
        echo -e "${YELLOW}📄 Files generated in: ${HELM_OUTPUT_PATH}${NC}"
    fi

    echo ""
    echo -e "${YELLOW}🔧 Useful commands:${NC}"
    echo "kubectl get pods -n ${NAMESPACE}"
    echo "kubectl get servicemonitors -n ${NAMESPACE}"
    if [[ "$INSTALL_SERVICES" == "true" ]]; then
        echo "kubectl get pods -n ${MAIN_API_NAMESPACE}"
        echo "kubectl get pods -n ${AUXILIARY_SERVICE_NAMESPACE}"
    fi
    echo ""
}

# Main function
main() {
    parse_args "$@"
    validate_config
    create_output_directories
    configure_access
    check_prerequisites
    setup_helm_repos
    create_namespaces
    install_services
    generate_passwords
    create_secrets
    create_monitoring_configs
    install_monitoring_stack
    apply_servicemonitors
    print_final_info

    log "🎉 Bootstrap completed successfully!"
}

# Run main function
main "$@"
