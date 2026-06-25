# 📘 Developer Playbook : Apps & GitOps Workflow

Ce dépôt (`aws-gitops-apps`) est la source de vérité pour tous les déploiements de nos applications sur le cluster EKS. Si cela n'existe pas dans ce dépôt Git, cela ne doit pas exister et ne survivra pas sur les serveurs de production.

---

## 1. 🐙 ArgoCD et la Mécanique GitOps

**Règle d'Or** : Ne faites jamais de `kubectl edit` ou `kubectl apply` sur les environnements supérieurs. ArgoCD écrase par défaut (`selfHeal = true`) toute modification manuelle dans le cluster pour correspondre au code présent dans Git.

**Le workflow d'un développeur** :
1. Pousse une PR sur ce dépôt avec ses modifications (ex: changement de variable d'environnement ou changement de version d'image).
2. Valide la PR via une review.
3. Après le `merge` sur la branche `main`, ArgoCD détectera automatiquement le changement et déploiera la modification de manière transparente sur le cluster d'ici 3 minutes maximum.
4. *(Optionnel)*: S'il y a urgence, vous pouvez aller sur la console Web ArgoCD et cliquer sur "Sync" pour appliquer la modification sans attendre.

---

## 2. 🚀 Onboarding : Publier un nouveau Microservice

Pour installer un nouveau service métier, voici la marche à suivre :

1. **Création des Manifestes Base** :
   Dans `gitops/apps/`, créez un répertoire au nom de votre service (ex: `my-backend/base`).
   Placez-y vos `deployment.yaml`, `service.yaml`, et `kustomization.yaml`.

2. **Création des Overlays (Environnements)** :
   Créez `my-backend/overlays/staging` et `my-backend/overlays/prod`.
   Grâce à *Kustomize*, modifiez uniquement le nombre de CPU/RAM, les variables d'environnement propres à la Prod, et le nom de l'image (si vous n'utilisez pas Argo Image Updater).

3. **Déclarer l'App à ArgoCD** :
   Créez un fichier Application (ex: `my-backend-prod.yaml`) à la racine de `gitops/apps/` :
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-backend-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/votre-orga/aws-gitops-apps.git'
    path: gitops/apps/my-backend/overlays/prod
    targetRevision: HEAD
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: my-backend
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

## 3. 🚦 Routing et Nom de Domaine (Istio)

Notre Service Mesh Istio achemine le trafic web vers les bons Pods.
Pour que `api.mon-projet.com` trouve votre service, vous n'avez pas besoin d'Ingress Controller basique, mais d'un `VirtualService`.

1. Créez un fichier `virtual-service.yaml` dans votre dossier `base/` :
```yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: my-backend
spec:
  hosts:
  - "api.mon-projet.com"
  gateways:
  - istio-system/public-gateway
  http:
  - match:
    - uri:
        prefix: /api/v1/
    route:
    - destination:
        host: my-backend-svc # Votre Service K8s
        port:
          number: 80
```
2. N'oubliez pas de l'inclure dans votre `kustomization.yaml`.
*`ExternalDNS` et `Cert-Manager` se chargeront du reste (DNS et Certificat SSL/HTTPS).*

---

## 4. 🔏 Gestion des Mots de Passe (Vault)

Aucune clé API critique ne doit être versionnée dans GitHub, même encodée en base64 pour k8s.
**Solution :**
1. Insérez le secret via l'UI Vault ou la CLI, dans le path de votre appli (ex: `secret/my-backend`).
2. Déclarez un `ExternalSecret` dans votre Repo GitOps :
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-backend-secret
spec:
  refreshInterval: "1h"
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: my-backend-env # Kubernetes créera dynamiquement CE secret
  data:
  - secretKey: STRIPE_KEY
    remoteRef:
      key: secret/my-backend
      property: STRIPE_SECRET_KEY
```
3. Votre pod utilisera `envFrom: secretRef: name: my-backend-env` dans son Deployment.

---

## 5. 🔵🟢 Déploiement "Zero Downtime" (Argo Rollouts)

Si votre application utilise le composant `Rollout` au lieu d'un `Deployment` classique, vous êtes protégé en cas de mauvaise version.

### Utiliser le Blue/Green Promotion
1. Lors du commit d'une nouvelle version de code (v2), ArgoCD déploie les Pods de la version v2 (Environnement *Green*) sans remplacer la v1 (*Blue*).
2. Aucun utilisateur n'est impacté.
3. Les développeurs testent la v2 de l'intérieur (port-forward ou header HTTP spécifique).
4. Si la v2 est validée, tapez cette commande ou utilisez l'UI d'Argo Rollouts pour basculer le trafic internet vers la v2 instantanément :
```bash
kubectl argo rollouts promote my-backend
```
5. Si vous ne validez pas, un "Abort" stoppera la procédure en détruisant les pods de la v2.

---
*Fin du GitOps Playbook.*
