# 🚀 Enhanced ArgoCD Deployment Options

The script now supports automatic application deployment with various levels of automation. Here are all the available options:

## 🎯 **Deployment Modes**

### **1. Basic Setup (Create Only)**
```bash
# Creates manifests and applications but doesn't deploy
./argocd-ingress-setup.sh \
  --domain argocd.local \
  --repo-url https://github.com/yourusername/kantox-challenge.git
```
**What it does:**
- ✅ Creates all manifests and Helm charts
- ✅ Creates ArgoCD application file
- ❌ Does NOT apply anything to cluster
- ✅ Perfect for GitOps review workflow

### **2. Quick Deploy (Apply Static Manifests)**
```bash
# Applies static manifests directly, bypassing ArgoCD
./argocd-ingress-setup.sh \
  --domain argocd.local \
  --repo-url https://github.com/yourusername/kantox-challenge.git \
  --apply-now
```
**What it does:**
- ✅ Creates all manifests
- ✅ Applies static Kubernetes manifests directly
- ❌ Does NOT deploy ArgoCD application
- ✅ Immediate ingress setup

### **3. GitOps Deploy (Deploy Application)**
```bash
# Deploys through ArgoCD application (GitOps way)
./argocd-ingress-setup.sh \
  --domain argocd.local \
  --repo-url https://github.com/yourusername/kantox-challenge.git \
  --deploy-app
```
**What it does:**
- ✅ Creates all manifests
- ✅ Deploys ArgoCD application
- ✅ ArgoCD manages the ingress deployment
- ❌ Doesn't wait for sync completion

### **4. Wait for Sync**
```bash
# Deploys and waits for successful sync
./argocd-ingress-setup.sh \
  --domain argocd.local \
  --repo-url https://github.com/yourusername/kantox-challenge.git \
  --deploy-app \
  --wait-for-sync
```
**What it does:**
- ✅ Creates and deploys ArgoCD application
- ✅ Waits up to 10 minutes for sync
- ✅ Automatically triggers sync if needed
- ✅ Reports final status

### **5. Full Deployment (Recommended)**
```bash
# Complete automated deployment
./argocd-ingress-setup.sh \
  --domain argocd.local \
  --repo-url https://github.com/yourusername/kantox-challenge.git \
  --full-deploy
```
**What it does:**
- ✅ Creates all manifests and charts
- ✅ Applies static manifests for immediate setup
- ✅ Deploys ArgoCD application for GitOps management
- ✅ Waits for application to sync and become healthy
- ✅ Verifies everything is working
- 🎯 **Best option for production setup**

## 🔄 **Sync Monitoring**

The enhanced script now provides detailed sync monitoring:

### **Real-time Status Updates**
```
[INFO] Waiting for ArgoCD application to sync...
[INFO] App Status - Sync: OutOfSync, Health: Unknown
[INFO] 🔄 Triggering application sync...
[INFO] App Status - Sync: Synced, Health: Progressing
[INFO] App Status - Sync: Synced, Health: Healthy
[SUCCESS] ✅ ArgoCD application synced and healthy!
```

### **Application Status Verification**
```
📱 ArgoCD Application Status:
   Name: argocd-ingress
   Sync Status: Synced
   Health Status: Healthy
[SUCCESS] ✅ Application is synced and healthy
```

## 🛠️ **Advanced Options**

### **Environment-Specific Deployment**
```bash
# Development
./argocd-ingress-setup.sh \
  --domain argocd.local \
  --full-deploy

# Staging
./argocd-ingress-setup.sh \
  --domain argocd-staging.yourdomain.com \
  --full-deploy

# Production with SSL
./argocd-ingress-setup.sh \
  --domain argocd.yourdomain.com \
  --full-deploy
```

### **Private Repository Setup**
```bash
# With GitHub credentials for private repo
./argocd-ingress-setup.sh \
  --domain argocd.local \
  --repo-url https://github.com/yourusername/private-repo.git \
  --github-user yourusername \
  --full-deploy
```

## 📊 **Post-Deployment Verification**

After running with `--deploy-app`, `--wait-for-sync`, or `--full-deploy`, you can verify:

### **Check Application Status**
```bash
# View all ArgoCD applications
kubectl get applications -n argocd

# Watch real-time sync status
kubectl get application argocd-ingress -n argocd -w

# Get detailed application info
kubectl describe application argocd-ingress -n argocd
```

### **Check Ingress Status**
```bash
# Verify ALB ingress
kubectl get ingress argocd-server-ingress -n argocd

# Check ALB hostname
kubectl get ingress argocd-server-ingress -n argocd \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### **Manual Sync Trigger**
```bash
# Force sync if needed
kubectl patch application argocd-ingress -n argocd \
  --type merge \
  -p='{"operation":{"sync":{"syncStrategy":{"apply":{"force":true}}}}}'
```

## 🚨 **Troubleshooting**

### **If Application Sync Fails**
1. **Check ArgoCD UI** at `http://your-domain`
2. **View application logs**:
   ```bash
   kubectl logs -n argocd deployment/argocd-application-controller
   ```
3. **Check repository access**:
   ```bash
   kubectl get secret github-repo-secret -n argocd
   ```

### **If Ingress Not Working**
1. **Check AWS Load Balancer Controller**:
   ```bash
   kubectl get deployment aws-load-balancer-controller -n kube-system
   ```
2. **Verify ALB creation**:
   ```bash
   aws elbv2 describe-load-balancers --region us-west-2
   ```

## 🎯 **Recommended Workflow for Kantox Challenge**

```bash
# 1. Initial setup with full deployment
./argocd-ingress-setup.sh \
  --domain argocd.local \
  --repo-url https://github.com/yourusername/kantox-challenge.git \
  --full-deploy

# 2. Verify everything is working
kubectl get applications -n argocd
kubectl get ingress argocd-server-ingress -n argocd

# 3. Access ArgoCD UI and add your main applications
# 4. Set up CI/CD pipeline to update manifests
# 5. Test GitOps workflow
```

This enhanced script now provides a complete, production-ready ArgoCD setup with full automation while maintaining GitOps best practices! 🎉