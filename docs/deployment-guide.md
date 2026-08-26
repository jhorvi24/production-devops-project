# Guía Paso a Paso: Despliegue en AWS (Linux)

## Prerequisitos

### 1. Instalar herramientas necesarias

```bash
# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version  # Verificar: aws-cli/2.x.x

# Terraform
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
terraform --version  # Verificar: Terraform v1.5+

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client

# Helm 3
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version

# Docker
sudo apt-get update
sudo apt-get install -y docker.io
sudo usermod -aG docker $USER
# Cerrar sesión y volver a entrar para que el grupo aplique
docker --version

# Git
sudo apt-get install -y git
git --version
```

### 2. Configurar AWS CLI

```bash
# Configurar credenciales (necesitas Access Key ID y Secret Access Key)
aws configure

# Te pedirá:
#   AWS Access Key ID: [tu-access-key]
#   AWS Secret Access Key: [tu-secret-key]
#   Default region name: us-east-1
#   Default output format: json

# Verificar que funciona:
aws sts get-caller-identity
# Debería mostrar tu Account ID, ARN, y User ID
```

**Si no tienes una cuenta AWS:**
1. Ve a https://aws.amazon.com/ → "Crear cuenta"
2. La capa gratuita (Free Tier) cubre algunos servicios, pero EKS NO está en Free Tier
3. Configura un presupuesto (Billing → Budgets) de $200/mes como alerta

---

## Paso a Paso del Despliegue

### Paso 1: Crear un repositorio en GitHub (5 min)

```bash
# En tu directorio del proyecto
cd ~/production-devops-projects

# Inicializar git
git init
git add .
git commit -m "feat: initial production incident simulator project"

# Crear repo en GitHub (necesitas GitHub CLI o hacerlo desde la web)
# Desde la web: github.com → New Repository → "production-devops-projects"

# Conectar y push
git remote add origin https://github.com/TU_USUARIO/production-devops-projects.git
git branch -M main
git push -u origin main
```

### Paso 2: Bootstrap del Backend de Terraform (3 min)

El bucket S3 necesita crearse ANTES de inicializar Terraform. El locking se maneja nativamente por S3 (`use_lockfile = true`), así que no necesitas DynamoDB.

```bash
# Usar el script
chmod +x scripts/bootstrap-backend.sh
./scripts/bootstrap-backend.sh

# O hacerlo manualmente:

# Crear bucket S3 para el state
aws s3api create-bucket \
  --bucket production-sim-terraform-state \
  --region us-east-1

# Habilitar versionado (para recuperar estados anteriores)
aws s3api put-bucket-versioning \
  --bucket production-sim-terraform-state \
  --versioning-configuration Status=Enabled

# Habilitar encriptación
aws s3api put-bucket-encryption \
  --bucket production-sim-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms"
      },
      "BucketKeyEnabled": true
    }]
  }'

# No se necesita DynamoDB: Terraform 1.10+ soporta locking nativo en S3
```

**Verificar:**
```bash
aws s3 ls | grep production-sim
# Debería mostrar: production-sim-terraform-state
```

### Paso 3: Desplegar infraestructura con Terraform (15-20 min)

```bash
# Ir al directorio del ambiente dev
cd terraform/environments/dev

# Inicializar Terraform (descarga providers y configura backend)
terraform init

# Ver qué se va a crear (sin aplicar cambios)
terraform plan

# Revisar el plan: debe mostrar ~30-40 recursos a crear
# Si todo se ve bien, aplicar:
terraform apply

# Escribir "yes" cuando pregunte
# Esto toma 15-20 minutos (EKS tarda ~10 min)
```

**¿Qué se está creando?**
- VPC con 3 subnets públicas + 3 privadas
- Internet Gateway + NAT Gateway
- EKS Cluster + 2 Worker Nodes (Spot)
- RDS PostgreSQL (db.t3.micro)
- Security Groups, IAM Roles, OIDC Provider

**Si hay errores:**
```bash
# Error de permisos IAM → Verificar que tu usuario tiene AdministratorAccess
# Error de límites → Verificar Service Quotas en tu cuenta
# Error de bucket → El nombre del bucket es global, puede estar tomado
#   Solución: Cambiar el nombre en terraform/backend.tf y bootstrap-backend.sh
```

### Paso 4: Configurar kubectl para conectar al cluster (1 min)

```bash
# Volver al directorio raíz del proyecto
cd ../../..

# Configurar kubectl con el cluster EKS recién creado
aws eks update-kubeconfig --name production-sim-dev --region us-east-1

# Verificar conexión
kubectl cluster-info
kubectl get nodes

# Deberías ver 2 nodos en estado "Ready"
```

### Paso 5: Aplicar manifests base de Kubernetes (2 min)

```bash
# Crear namespaces, RBAC, Network Policies
kubectl apply -f k8s/base/namespaces.yaml
kubectl apply -f k8s/base/rbac.yaml
kubectl apply -f k8s/base/network-policies.yaml
kubectl apply -f k8s/base/limit-ranges.yaml
kubectl apply -f k8s/base/resource-quotas.yaml

# Verificar
kubectl get namespaces
# Deberías ver: applications, monitoring, argocd, ingress
```

### Paso 6: Instalar ArgoCD (5 min)

```bash
# Instalar ArgoCD en el cluster
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Esperar a que esté listo (puede tardar 2-3 min)
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

# Obtener la contraseña del admin
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD Password: $ARGOCD_PASSWORD"

# Guardar esa contraseña! La necesitas para el UI.

# Acceder al UI de ArgoCD (abrir en otra terminal):
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Abrir en el navegador: https://localhost:8080
# User: admin
# Password: (la que obtuviste arriba)
```

### Paso 7: Build y Push de imágenes Docker a ECR (10 min)

Antes de que ArgoCD pueda desplegar, necesitas las imágenes en ECR:

```bash
# Obtener tu Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"

# Login a ECR
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

# Crear repositorios ECR (si no los creó Terraform)
aws ecr create-repository --repository-name production-sim/api-gateway --region $REGION 2>/dev/null || true
aws ecr create-repository --repository-name production-sim/order-service --region $REGION 2>/dev/null || true
aws ecr create-repository --repository-name production-sim/payment-service --region $REGION 2>/dev/null || true

# Generar lockfiles necesarios para los builds
cd apps/api-gateway && npm install && cd ../..

# Build y push de cada microservicio

# API Gateway
docker build -t "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/production-sim/api-gateway:latest" apps/api-gateway/
docker push "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/production-sim/api-gateway:latest"

# Order Service
docker build -t "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/production-sim/order-service:latest" apps/order-service/
docker push "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/production-sim/order-service:latest"

# Payment Service
docker build -t "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/production-sim/payment-service:latest" apps/payment-service/
docker push "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/production-sim/payment-service:latest"
```

### Paso 8: Actualizar manifests con tu Account ID (2 min)

Los manifests tienen `ACCOUNT_ID` como placeholder. Necesitas reemplazarlo:

```bash
# Reemplazar ACCOUNT_ID en todos los manifests de Kubernetes
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Actualizar deployments
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" k8s/apps/api-gateway/deployment.yaml
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" k8s/apps/order-service/deployment.yaml
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" k8s/apps/payment-service/deployment.yaml
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" k8s/apps/ingress.yaml
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" k8s/base/rbac.yaml

# Commit y push
git add k8s/
git commit -m "ci: update manifests with AWS account ID"
git push origin main
```

### Paso 9: Crear Kubernetes Secret para la DB (1 min)

```bash
# Obtener credenciales de RDS desde Terraform output
cd terraform/environments/dev
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
cd ../../..

# Obtener password desde Secrets Manager
DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id production-sim-dev-db-credentials \
  --query 'SecretString' --output text | jq -r '.password')

# Crear secret en Kubernetes
kubectl create secret generic db-credentials \
  --namespace=applications \
  --from-literal=host=$(echo $RDS_ENDPOINT | cut -d: -f1) \
  --from-literal=port=5432 \
  --from-literal=dbname=production_sim \
  --from-literal=username=dbadmin \
  --from-literal=password=$DB_PASSWORD
```

### Paso 10: Desplegar aplicaciones con ArgoCD (3 min)

```bash
# Actualizar las URLs del repositorio en los manifests de ArgoCD
# Reemplazar YOUR_USERNAME con tu usuario de GitHub
GITHUB_USER="TU_USUARIO"

sed -i "s/YOUR_USERNAME/$GITHUB_USER/g" k8s/argocd/applications/*.yaml
sed -i "s/YOUR_USERNAME/$GITHUB_USER/g" k8s/argocd/project.yaml

git add k8s/argocd/
git commit -m "ci: update ArgoCD repo URLs"
git push origin main

# Aplicar el proyecto y la app-of-apps
kubectl apply -f k8s/argocd/project.yaml
kubectl apply -f k8s/argocd/applications/app-of-apps.yaml

# Verificar en ArgoCD UI que las aplicaciones se están sincronizando
# https://localhost:8080
```

### Paso 11: Verificar el despliegue (5 min)

```bash
# Ver todos los pods
kubectl get pods -A

# Ver pods de aplicaciones
kubectl get pods -n applications

# Todos deben estar en estado Running
# Si alguno está en CrashLoopBackOff:
# kubectl logs -n applications <pod-name>

# Verificar services
kubectl get svc -n applications

# Test funcional
kubectl exec -n applications deploy/api-gateway -- \
  curl -s http://localhost:3000/health/ready

# Ver el Ingress (ALB)
kubectl get ingress -n applications
```

---

## Verificación Final

```bash
echo "=== Verificación del Despliegue ==="

# 1. Nodos
echo -e "\n[1] Nodos EKS:"
kubectl get nodes

# 2. Pods
echo -e "\n[2] Pods de aplicaciones:"
kubectl get pods -n applications

# 3. Services
echo -e "\n[3] Services:"
kubectl get svc -n applications

# 4. ArgoCD
echo -e "\n[4] ArgoCD Applications:"
kubectl get applications -n argocd

# 5. Health check
echo -e "\n[5] Health Check:"
kubectl exec -n applications deploy/api-gateway -- \
  curl -s http://localhost:3000/health/ready | jq .
```

---

## Practicar Incidentes

Una vez todo está corriendo:

```bash
# Dar permisos de ejecución a los scripts
chmod +x scripts/*.sh

# Ver escenarios disponibles
./scripts/inject-fault.sh --list

# Inyectar un incidente
./scripts/inject-fault.sh --scenario memory-leak

# Seguir el runbook para resolver:
# cat incidents/runbooks/memory-leak.md

# Limpiar cuando termines
./scripts/inject-fault.sh --cleanup memory-leak
```

---

## Destruir Todo (cuando termines de practicar)

```bash
# IMPORTANTE: Destruir para no seguir pagando (~$6-7/día)

# Opción A: Usar el script
chmod +x scripts/teardown.sh
./scripts/teardown.sh dev

# Opción B: Paso a paso manual

# 1. Eliminar apps de ArgoCD
kubectl delete -f k8s/argocd/applications/ --ignore-not-found

# 2. Esperar 30 segundos
sleep 30

# 3. Eliminar namespaces
kubectl delete namespace applications monitoring ingress --ignore-not-found

# 4. Esperar a que se eliminen los Load Balancers
echo "Esperando eliminación de ALBs (60s)..."
sleep 60

# 5. Destruir infraestructura con Terraform
cd terraform/environments/dev
terraform destroy
# Escribir "yes" cuando pregunte (toma 10-15 minutos)

# 6. (Opcional) Eliminar el backend
aws s3 rb s3://production-sim-terraform-state --force
```

---

## Costos Esperados

| Recurso | Costo/hora | Costo/día |
|---------|-----------|-----------|
| EKS Control Plane | $0.10 | $2.40 |
| 2x t3.medium Spot | ~$0.02 | ~$0.96 |
| RDS db.t3.micro | $0.018 | $0.43 |
| NAT Gateway | $0.045 | $1.08 |
| ALB | $0.023 | $0.55 |
| **Total estimado** | | **~$5-7/día** |

**Tip:** Despliega por la mañana, practica, y destruye por la noche. Un día de práctica cuesta ~$6.

---

## Troubleshooting Común

### "terraform init falla con error de backend"
```bash
# Verificar que el bucket existe
aws s3 ls | grep production-sim
# Si no existe → ejecutar Paso 2 primero
```

### "kubectl no puede conectar al cluster"
```bash
# Re-generar kubeconfig
aws eks update-kubeconfig --name production-sim-dev --region us-east-1
# Verificar que el cluster existe
aws eks list-clusters --region us-east-1
```

### "Pods en ImagePullBackOff"
```bash
# Las imágenes no están en ECR o los nodos no tienen permiso
# Verificar que las imágenes existen:
aws ecr list-images --repository-name production-sim/api-gateway --region us-east-1
# Verificar permisos del node role (debe tener AmazonEC2ContainerRegistryReadOnly)
```

### "Pods en Pending (no se schedulean)"
```bash
# Verificar eventos del pod
kubectl describe pod <pod-name> -n applications
# Típicamente: Insufficient cpu/memory
# Verificar nodos:
kubectl get nodes
kubectl describe nodes | grep -A5 "Allocatable"
```

### "RDS connection refused"
```bash
# Verificar que el Security Group permite tráfico desde EKS
# Verificar el secret:
kubectl get secret db-credentials -n applications -o jsonpath='{.data.host}' | base64 -d
echo ""
```

### "NAT Gateway: limite de EIPs"
```bash
# Verificar cuotas
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-0263D0A3 \
  --query 'Quota.Value'
# Si estás en el límite, solicitar aumento desde la consola AWS
```
