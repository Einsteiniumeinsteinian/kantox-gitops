#!/bin/bash

# =============================================================================
# Monitoring Stack Cleanup/Destroy Script - Fixed to Match Bootstrap
# Safely removes all monitoring infrastructure created by bootstrap script
# =============================================================================

set -e  # Exit on any error

# Configuration (matches bootstrap script exactly)
DOMAIN="${DOMAIN:-}"
NAMESPACE="${NAMESPACE:-monitoring}"
CLEANUP_MODE="${CLEANUP_MODE:-selective}"  # Options: "selective", "complete", "files-only"
FORCE_DELETE="${FORCE_DELETE:-false}"
DRY_RUN="${DRY_RUN:-false}"

# Service Configuration (matches bootstrap)
MAIN_API_NAMESPACE="${MAIN_API_NAMESPACE:-main-api}"
AUXILIARY_SERVICE_NAMESPACE="${AUXILIARY_SERVICE_NAMESPACE:-auxiliary-service}"
CLEANUP_SERVICES="${CLEANUP_SERVICES:-true}"  # Whether to clean up services too

# Output paths (matches bootstrap script exactly)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBERNETES_OUTPUT_PATH="${KUBERNETES_OUTPUT_PATH:-${SCRIPT_DIR}/../deployments/monitoring/k8s}"
HELM_OUTPUT_PATH="${HELM_OUTPUT_PATH:-${SCRIPT_DIR}/../deployments/monitoring/helm}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging functions
log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARNING] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; exit 1; }
info() { echo -e "${BLUE}[INFO] $1${NC}"; }
dry_run_log() { [[ "$DRY_RUN" == "true" ]] && echo -e "${CYAN}[DRY-RUN] Would execute: $1${NC}"; }

# Show help
show_help() {
    cat << EOF
Monitoring Stack Cleanup Script (Matches Bootstrap)

USAGE: $0 [OPTIONS]

REQUIRED (for safety):
    --domain DOMAIN             Domain used in deployment (validation)

OPTIONS:
    --namespace NAMESPACE       Monitoring namespace (default: monitoring)
    --mode MODE                 Cleanup mode: selective, complete, files-only (default: selective)
    --force                     Skip confirmation prompts
    --dry-run                   Show what would be deleted
    --skip-services             Don't clean up main-api/auxiliary-service
    -h, --help                  Show this help

CLEANUP MODES:
    selective   - Remove monitoring stack, preserve data (safest)
    complete    - Remove everything including data (dangerous!)
    files-only  - Only delete generated files

EXAMPLES:
    # Safe cleanup
    $0 --domain monitoring.company.com

    # Preview what would be deleted
    $0 --domain monitoring.company.com --dry-run

    # Complete cleanup (deletes data!)
    $0 --domain monitoring.company.com --mode complete

    # Only remove files
    $0 --mode files-only
EOF
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --domain) DOMAIN="$2"; shift 2 ;;
            --namespace) NAMESPACE="$2"; shift 2 ;;
            --mode) CLEANUP_MODE="$2"; shift 2 ;;
            --force) FORCE_DELETE="true"; shift ;;
            --dry-run) DRY_RUN="true"; shift ;;
            --skip-services) CLEANUP_SERVICES="false"; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) echo "Unknown option: $1"; show_help; exit 1 ;;
        esac
    done
}

# Validate configuration
validate_config() {
    log "Validating cleanup configuration..."
    
    case $CLEANUP_MODE in
        "selective"|"complete"|"files-only") ;;
        *) error "Invalid CLEANUP_MODE: $CLEANUP_MODE" ;;
    esac
    
    # Require domain for cluster operations (safety)
    if [[ "$CLEANUP_MODE" != "files-only" ]]; then
        [[ -z "$DOMAIN" ]] && error "DOMAIN required for cluster cleanup (safety check)"
    fi
    
    log "✅ Configuration validated"
}

# Check prerequisites
check_prerequisites() {
    if [[ "$CLEANUP_MODE" != "files-only" ]]; then
        command -v kubectl >/dev/null 2>&1 || error "kubectl not installed"
        command -v helm >/dev/null 2>&1 || error "helm not installed"
        kubectl cluster-info >/dev/null 2>&1 || error "Cannot connect to cluster"
    fi
}

# Execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${CYAN}[DRY-RUN] $description${NC}"
        echo -e "${CYAN}[DRY-RUN] Command: $cmd${NC}"
    else
        log "$description"
        eval "$cmd" || warn "Command failed (might be already deleted): $cmd"
    fi
}

# Confirm action
confirm_action() {
    local action="$1"
    local details="$2"
    
    if [[ "$FORCE_DELETE" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    warn "⚠️  CONFIRMATION: $action"
    [[ -n "$details" ]] && echo "Details: $details"
    echo "Domain: $DOMAIN"
    echo "Namespace: $NAMESPACE"
    read -p "Proceed? [y/N]: " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 0
}

# Check existing resources
check_existing_resources() {
    log "Checking existing resources..."
    
    local found=false
    
    if [[ "$CLEANUP_MODE" != "files-only" ]]; then
        # Check monitoring stack
        if helm list -n "$NAMESPACE" 2>/dev/null | grep -q prometheus; then
            info "📦 Found monitoring stack"
            found=true
        fi
        
        # Check services (matches bootstrap)
        if [[ "$CLEANUP_SERVICES" == "true" ]]; then
            if helm list -n "$MAIN_API_NAMESPACE" 2>/dev/null | grep -q main-api; then
                info "🚀 Found main-api service"
                found=true
            fi
            
            if helm list -n "$AUXILIARY_SERVICE_NAMESPACE" 2>/dev/null | grep -q auxiliary-service; then
                info "🔧 Found auxiliary-service"
                found=true
            fi
        fi
        
        # Check secrets (matches what bootstrap creates)
        if kubectl get secret grafana-admin-secret -n "$NAMESPACE" >/dev/null 2>&1; then
            info "🔐 Found grafana-admin-secret"
            found=true
        fi
        
        # Check data (PVCs)
        local pvc_count=$(kubectl get pvc -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
        if [[ $pvc_count -gt 0 ]]; then
            warn "💾 Found $pvc_count PVCs (monitoring data!)"
            found=true
        fi
    fi
    
    # Check files (matches bootstrap paths)
    if [[ -d "$KUBERNETES_OUTPUT_PATH" || -d "$HELM_OUTPUT_PATH" ]]; then
        info "📄 Found generated files"
        found=true
    fi
    
    if [[ "$found" == "false" ]]; then
        log "✅ No resources found to clean up"
        exit 0
    fi
}

# Clean up services (matches bootstrap)
cleanup_services() {
    if [[ "$CLEANUP_SERVICES" != "true" || "$CLEANUP_MODE" == "files-only" ]]; then
        return 0
    fi
    
    log "Cleaning up application services..."
    
    # Remove auxiliary-service first (reverse order of bootstrap)
    if helm list -n "$AUXILIARY_SERVICE_NAMESPACE" 2>/dev/null | grep -q auxiliary-service; then
        confirm_action "Remove auxiliary-service" "Namespace: $AUXILIARY_SERVICE_NAMESPACE"
        execute_cmd "helm uninstall auxiliary-service -n '$AUXILIARY_SERVICE_NAMESPACE'" "Removing auxiliary-service"
    fi
    
    # Remove main-api
    if helm list -n "$MAIN_API_NAMESPACE" 2>/dev/null | grep -q main-api; then
        confirm_action "Remove main-api" "Namespace: $MAIN_API_NAMESPACE"
        execute_cmd "helm uninstall main-api -n '$MAIN_API_NAMESPACE'" "Removing main-api"
    fi
}

# Clean up monitoring stack
cleanup_monitoring() {
    if [[ "$CLEANUP_MODE" == "files-only" ]]; then
        return 0
    fi
    
    log "Cleaning up monitoring stack..."
    
    # Remove monitoring ingress
    if kubectl get ingress monitoring-ingress -n "$NAMESPACE" >/dev/null 2>&1; then
        execute_cmd "kubectl delete ingress monitoring-ingress -n '$NAMESPACE'" "Removing monitoring ingress"
    fi
    
    # Remove ServiceMonitors (matches bootstrap)
    if kubectl get servicemonitor -n "$NAMESPACE" >/dev/null 2>&1; then
        execute_cmd "kubectl delete servicemonitor main-api-monitor auxiliary-service-monitor -n '$NAMESPACE' --ignore-not-found" "Removing ServiceMonitors"
    fi
    
    # Remove Helm release
    if helm list -n "$NAMESPACE" 2>/dev/null | grep -q prometheus; then
        confirm_action "Remove monitoring stack" "This removes Prometheus, Grafana, AlertManager"
        execute_cmd "helm uninstall prometheus -n '$NAMESPACE'" "Removing monitoring Helm release"
    fi
}

# Clean up secrets and data
cleanup_secrets_and_data() {
    if [[ "$CLEANUP_MODE" != "complete" ]]; then
        return 0
    fi
    
    log "Cleaning up secrets and data..."
    
    # Remove secrets (matches what bootstrap creates)
    if kubectl get secret grafana-admin-secret -n "$NAMESPACE" >/dev/null 2>&1; then
        execute_cmd "kubectl delete secret grafana-admin-secret -n '$NAMESPACE'" "Removing grafana-admin-secret"
    fi
    
    # Remove PVCs (DATA LOSS!)
    local pvcs=$(kubectl get pvc -n "$NAMESPACE" --no-headers -o name 2>/dev/null || echo "")
    if [[ -n "$pvcs" ]]; then
        confirm_action "Delete monitoring data" "⚠️  THIS DELETES ALL MONITORING DATA!"
        execute_cmd "kubectl delete pvc --all -n '$NAMESPACE'" "Removing PVCs (deleting data)"
    fi
}

# Clean up files (matches bootstrap paths)
cleanup_files() {
    log "Cleaning up generated files..."
    
    local files_removed=false
    
    # Remove Kubernetes files (matches bootstrap path)
    if [[ -d "$KUBERNETES_OUTPUT_PATH" ]]; then
        confirm_action "Delete Kubernetes files" "$KUBERNETES_OUTPUT_PATH"
        execute_cmd "rm -rf '$KUBERNETES_OUTPUT_PATH'" "Removing Kubernetes files"
        files_removed=true
    fi
    
    # Remove Helm files (matches bootstrap path)
    if [[ -d "$HELM_OUTPUT_PATH" ]]; then
        confirm_action "Delete Helm files" "$HELM_OUTPUT_PATH"
        execute_cmd "rm -rf '$HELM_OUTPUT_PATH'" "Removing Helm files"
        files_removed=true
    fi
    
    # Remove parent directory if empty
    if [[ "$files_removed" == "true" ]]; then
        local parent_monitoring="${KUBERNETES_OUTPUT_PATH}/.."
        if [[ -d "$parent_monitoring" ]]; then
            execute_cmd "rmdir '$parent_monitoring' 2>/dev/null || true" "Cleaning up empty monitoring directory"
        fi
    fi
}

# Print summary
print_summary() {
    echo ""
    echo "🎉 CLEANUP COMPLETED!"
    echo "===================="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${CYAN}🔍 DRY RUN - No changes made${NC}"
        echo "Run without --dry-run to execute"
        return
    fi
    
    echo -e "${BLUE}Cleaned up:${NC}"
    echo "- Domain: ${DOMAIN:-N/A}"
    echo "- Mode: $CLEANUP_MODE"
    echo "- Services: $([[ "$CLEANUP_SERVICES" == "true" ]] && echo "Yes" || echo "No")"
    
    echo ""
    echo -e "${YELLOW}Verification:${NC}"
    echo "helm list -n $NAMESPACE"
    if [[ "$CLEANUP_SERVICES" == "true" ]]; then
        echo "helm list -n $MAIN_API_NAMESPACE"
        echo "helm list -n $AUXILIARY_SERVICE_NAMESPACE"
    fi
    echo "kubectl get all -n $NAMESPACE"
    echo "ls -la $KUBERNETES_OUTPUT_PATH 2>/dev/null || echo 'Files removed'"
}

# Main function
main() {
    echo ""
    echo -e "${RED}🧹 MONITORING CLEANUP${NC}"
    echo "====================="
    
    parse_args "$@"
    validate_config
    check_prerequisites
    check_existing_resources
    
    # Print what will be done
    echo ""
    echo -e "${BLUE}Cleanup Plan:${NC}"
    echo "Domain: ${DOMAIN:-N/A}"
    echo "Mode: $CLEANUP_MODE"
    echo "Services: $([[ "$CLEANUP_SERVICES" == "true" ]] && echo "Will clean" || echo "Will skip")"
    echo "Dry Run: $DRY_RUN"
    echo ""
    
    # Execute cleanup
    case $CLEANUP_MODE in
        "selective")
            cleanup_services
            cleanup_monitoring
            cleanup_files
            ;;
        "complete")
            cleanup_services
            cleanup_monitoring
            cleanup_secrets_and_data
            cleanup_files
            ;;
        "files-only")
            cleanup_files
            ;;
    esac
    
    print_summary
    log "Cleanup completed successfully!"
}

# Run main function
main "$@"