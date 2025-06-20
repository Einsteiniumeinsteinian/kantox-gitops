# Kantox Cloud Engineer Challenge - GitOps Repository

[![GitOps](https://img.shields.io/badge/GitOps-ArgoCD-blue.svg)](https://argoproj.github.io/argo-cd/)
[![AWS](https://img.shields.io/badge/Cloud-AWS-orange.svg)](https://aws.amazon.com/)
[![Kubernetes](https://img.shields.io/badge/Platform-Kubernetes-326CE5.svg)](https://kubernetes.io/)
[![Helm](https://img.shields.io/badge/Packaging-Helm-0F1689.svg)](https://helm.sh/)

A GitOps-based Kubernetes deployment repository for the Kantox Cloud Engineer Challenge, implementing microservices deployment using ArgoCD, Helm, and AWS infrastructure.

## 📁 Repository Structure

```text
.
├── argocd/                          
│   ├── applications/               
│   │   ├── argocd-ingress-application.yaml    
│   │   ├── auxiliary-service-application.yaml
│   │   ├── main-api-application.yaml         
│   │   ├── monitoring-application.yaml        
│   │   └── ingress.yaml                       
│   └── app-of-apps.yaml       
│
├── deployments/                     
│   ├── argocd/                     
│   │   ├── helm/                  
│   │   │   ├── Chart.yaml
│   │   │   ├── templates/
│   │   │   │   ├── _helpers.tpl
│   │   │   │   ├── ingress.yaml
│   │   │   │   └── server-config.yaml
│   │   │   ├── values.yaml
│   │   │   ├── values-staging.yaml
│   │   │   └── values-prod.yaml
│   │   └── kubernetes/ 
│   │       ├── ingress.yaml
│   │       └── server-config.yaml
│   │
│   ├── auxiliary-service/          
│   │   ├── helm/                   
│   │   │   ├── Chart.yaml
│   │   │   ├── templates/
│   │   │   │   ├── configmap.yaml
│   │   │   │   ├── deployment.yaml
│   │   │   │   ├── service.yaml
│   │   │   │   ├── ingress.yaml
│   │   │   │   ├── hpa.yaml           
│   │   │   │   ├── vpa.yaml          
│   │   │   │   ├── pdb.yaml           
│   │   │   │   ├── networkpolicy.yaml 
│   │   │   │   ├── rbac.yaml          
│   │   │   │   ├── serviceaccount.yaml
│   │   │   │   ├── servicemonitor.yaml 
│   │   │   │   ├── limitrange.yaml    
│   │   │   │   ├── resourcequota.yaml
│   │   │   │   └── _helpers.tpl.yaml
│   │   │   ├── values.yaml        
│   │   │   ├── values-staging.yaml 
│   │   │   └── values-prod.yaml   
│   │   └── kubernetes/             
│   │       ├── configMap.yaml
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       ├── hpa.yaml
│   │       ├── vpa.yaml
│   │       ├── pdb.yaml
│   │       ├── networkPolicy.yaml
│   │       ├── role.yaml
│   │       ├── serviceAccount.yaml
│   │       ├── serviceLimits.yaml
│   │       └── resourceQuota.yaml
│   │
│   ├── main-api/                   # Main API Service
│   │   ├── helm/                   # Helm chart
│   │   │   ├── Chart.yaml
│   │   │   ├── templates/
│   │   │   │   ├── configmap.yaml
│   │   │   │   ├── deployment.yaml
│   │   │   │   ├── service.yaml
│   │   │   │   ├── ingress.yaml
│   │   │   │   ├── hpa.yaml
│   │   │   │   ├── vpa.yaml
│   │   │   │   ├── pdb.yaml
│   │   │   │   ├── networkpolicy.yaml
│   │   │   │   ├── rbac.yaml
│   │   │   │   ├── serviceaccount.yaml
│   │   │   │   ├── servicemonitor.yaml
│   │   │   │   ├── limitrange.yaml
│   │   │   │   ├── resourcequota.yaml
│   │   │   │   └── _helpers.tpl.yaml
│   │   │   ├── values.yaml
│   │   │   ├── values-staging.yaml
│   │   │   └── values-prod.yaml
│   │   └── kubernetes/             
│   │       ├── configMap.yaml
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       ├── ingress.yaml
│   │       ├── hpa.yaml
│   │       ├── vpa.yaml
│   │       ├── pdb.yaml
│   │       ├── networkPolicy.yaml
│   │       ├── role.yaml
│   │       ├── serviceAccount.yaml
│   │       ├── serviceLimits.yaml
│   │       └── resourceQuota.yaml
│   │
│   └── monitoring/                 
│       ├── helm/                  
│       │   └── values.yaml
│       └── k8s/                    
│           ├── ingress.yaml
│           └── servicemonitors.yaml
│
├── docs/                           
│   ├── argocd-setup.md            
│   ├── monitoring-bootstrap.md     
│   └── monitoring-cleanup.md      
│
└── scripts/                       
    ├── argocd-setup.sh            
    ├── monitoring-bootstrap.sh     
    └── monitoring-cleanup.sh       
```

## 🎯 Directory Purpose

### **argocd/**

Contains ArgoCD application definitions and the app-of-apps pattern configuration.

- **applications/**: Individual ArgoCD application manifests
- **app-of-apps.yaml**: Root application that manages all other applications

### **deployments/**

Kubernetes deployment configurations for all services.

#### **deployments/argocd/**

ArgoCD ingress configuration with AWS ALB integration.

- **helm/**: Helm chart for ArgoCD ingress with environment-specific values
- **kubernetes/**: Static Kubernetes manifests for direct deployment

#### **deployments/auxiliary-service/**

Auxiliary service that handles AWS integrations for the main API.

- **helm/**: Complete Helm chart with production-ready templates
- **kubernetes/**: Static manifests for non-Helm deployments

#### **deployments/main-api/**

Main REST API service exposing AWS S3 and Parameter Store endpoints.

- **helm/**: Complete Helm chart with comprehensive templates
- **kubernetes/**: Static manifests alternative

#### **deployments/monitoring/**

Prometheus and Grafana monitoring stack.

- **helm/**: Monitoring configuration values
- **k8s/**: ServiceMonitors and ingress configurations

### **docs/**

Project documentation and operational guides.

### **scripts/**

Automation scripts for setup, deployment, and maintenance.

## 🚀 Quick Start

### Deploy ArgoCD with Ingress

```bash
./scripts/argocd-setup.sh \
  --domain argocd.yourdomain.com \
  --repo-url https://github.com/yourusername/kantox-gitops.git \
  --full-deploy
```

### Deploy All Applications via App-of-Apps

```bash
kubectl apply -f argocd/app-of-apps.yaml
```

### Check Application Status

```bash
kubectl get applications -n argocd
```

## 🏗️ Architecture

This repository implements a **GitOps workflow** where:

1. **ArgoCD** monitors this Git repository
2. **Applications** are defined in `argocd/applications/`
3. **Deployments** are sourced from `deployments/` directory
4. **Environment-specific** configurations via Helm values files
5. **Automated sync** keeps cluster state matching Git state

## 🔄 GitOps Workflow

1. **Code changes** pushed to this repository
2. **ArgoCD detects** changes automatically
3. **Applications sync** to match Git state
4. **Kubernetes resources** updated accordingly

## 🌍 Environment Support

Each service supports three environments:

- **Development**: `values.yaml`
- **Staging**: `values-staging.yaml`
- **Production**: `values-prod.yaml`

## 🛠️ Deployment Methods

### Via ArgoCD (Recommended)

```bash
kubectl apply -f argocd/applications/main-api-application.yaml
```

### Via Helm

```bash
helm upgrade --install main-api deployments/main-api/helm/ \
  --values deployments/main-api/helm/values-prod.yaml
```

### Via kubectl

```bash
kubectl apply -f deployments/main-api/kubernetes/
```

---

## 📚 Additional Information

For more detailed information on scripts and operational procedures, check the docs folder.

**Part of the Kantox Cloud Engineer Challenge - demonstrating GitOps best practices with ArgoCD and Kubernetes.**
