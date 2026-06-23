# AWS GitOps Apps

Ce dépôt contient les manifestes Kubernetes et la configuration GitOps (ArgoCD) pour déployer vos applications et vos outils d'infrastructure sur le cluster EKS provisionné par Terraform.

## Structure du Dépôt

```
aws-gitops-apps/
├── .github/
│   └── workflows/          # Workflows CI/CD (ex: promotion)
├── gitops/
│   ├── apps/               # Manifestes de vos applications métier
│   │   ├── frontend/       # Exemple d'app frontend avec Blue/Green
│   │   ├── backend/        # Exemple d'app backend avec Canary & Auto-promotion
│   │   ├── worker/         # Exemple de worker (Deployment classique)
│   │   └── mon-app/        # Squelette minimaliste
│   ├── base/               # Outils fondationnels (Istio, Cert-Manager, ExternalDNS, Vault)
│   └── tools/              # Outils supplémentaires (Argo Rollouts, Prometheus, Velero, Image Updater)
└── README.md
```

## 🚀 Onboarding d'une Nouvelle Application

Pour ajouter une nouvelle application, suivez ces étapes :

1. **Créer la structure du répertoire**
   Copiez un des exemples existants (ex: `backend/`) dans `gitops/apps/mon-nouveau-service`.
2. **Adapter les manifestes de base**
   Dans `gitops/apps/mon-nouveau-service/base/` :
   - Modifiez le `kustomization.yaml`.
   - Modifiez `rollout.yaml` (ou `deployment.yaml`) pour pointer vers votre image.
   - Modifiez `service.yaml` et `virtual-service.yaml` (pour configurer le routage Istio).
3. **Adapter les environnements (Overlays)**
   Dans `gitops/apps/mon-nouveau-service/overlays/` :
   - Configurez `staging` et `prod` (Kustomization, variables, replicas).
4. **Déclarer l'application à ArgoCD**
   - Créez un fichier `mon-nouveau-service-staging.yaml` et `mon-nouveau-service-prod.yaml` à la racine de `gitops/apps/`.
   - Mettez à jour les liens de chemins (paths) dans ces fichiers.

## 🔄 Stratégies de Déploiement et Promotion

Ce dépôt met en évidence plusieurs stratégies de déploiement et de promotion vers la production :

### 1. Promotion Automatisée avec ArgoCD Image Updater (Ex: Backend)
Le `backend` est configuré avec l'**ArgoCD Image Updater**.
- Lorsqu'une nouvelle image Docker (`v1.x.x`) est poussée sur le registre, l'Image Updater la détecte.
- L'Updater **commit automatiquement** la mise à jour (Write-Back) dans ce dépôt Git dans l'environnement configuré.
- ArgoCD déploie ensuite le changement (ex: avec un déploiement Canary via Argo Rollouts).

### 2. Promotion Manuelle ou par CI/CD avec Approval Gates (Ex: Frontend)
Le `frontend` nécessite une validation manuelle.
- L'image de Staging est mise à jour par la CI.
- Pour passer en Production, un utilisateur doit approuver via une Pull Request, ou utiliser le Workflow GitHub Actions "Promote to Production".
- Le déploiement s'effectue via un **Blue/Green** (Argo Rollouts) : la nouvelle version est déployée en parallèle, et un clic dans ArgoCD (ou une commande `kubectl argo rollouts promote`) permet de basculer le trafic.

## 🛡️ Sécurité & Gouvernance

### Protections de Branche (GitHub)
Il est critique d'empêcher les pushs directs sur la branche `main` pour garantir que tout changement d'infrastructure est revu.

**Pour configurer la protection de branche via GitHub :**
1. Allez dans **Settings > Branches** de votre dépôt.
2. Cliquez sur **Add branch protection rule**.
3. **Branch name pattern** : `main`
4. Cochez **Require a pull request before merging**.
   - Cochez *Require approvals* (min: 1).
5. Cochez **Require status checks to pass before merging** (pour s'assurer que vos CI passent avant de merge).
6. Cliquez sur **Create**.

### Gestion des Secrets
Les secrets ne doivent **jamais** être stockés dans ce dépôt. Utilisez Vault et External Secrets Operator. (Voir README du dépôt `aws-gitops-infrastructure`).

## 💾 Sauvegardes (Velero)
Velero est installé (`gitops/tools/velero.yaml`) et un `Schedule` est configuré (`gitops/tools/manifests/velero-schedule.yaml`) pour sauvegarder automatiquement le cluster chaque nuit à 2h00 du matin.
Les sauvegardes sont envoyées vers le bucket S3 provisionné par Terraform.

---
*Ce dépôt est conçu pour fonctionner en tandem avec le dépôt `aws-gitops-infrastructure`.*
