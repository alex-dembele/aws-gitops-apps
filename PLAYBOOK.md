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

## 2. 🚀 Onboarding : Déployer un projet de bout en bout (App of Apps)

Notre cluster est configuré avec un **ApplicationSet** (le pattern *App of Apps*). Cela signifie qu'ArgoCD scanne constamment ce dépôt Git. Dès que vous ajoutez un nouveau dossier dans `gitops/apps/`, l'Application est **automatiquement reconnue et créée** sans aucune configuration supplémentaire côté Argo !

### Tutoriel de bout en bout (End-to-End) :

**Étape 1 : Créer la hiérarchie de votre application**
1. Sur votre branche locale, créez le dossier : `mkdir -p gitops/apps/mon-nouveau-backend/base`
2. Créez également vos dossiers d'environnements : `mkdir -p gitops/apps/mon-nouveau-backend/overlays/prod`

**Étape 2 : Les Manifestes de Base (`/base`)**
1. Placez votre `deployment.yaml` (ou `rollout.yaml`).
2. Placez votre `service.yaml` (ex: ciblant le port 8080).
3. Placez votre `virtual-service.yaml` Istio pour router `api.votre-domaine.com` vers votre Service K8s.
4. Créez un `kustomization.yaml` dans `/base` :
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
  - virtual-service.yaml
```

**Étape 3 : Spécifier la Production (`/overlays/prod`)**
1. Créez un `kustomization.yaml` dans `/overlays/prod` :
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namePrefix: prod-
images:
  - name: mon-image-app
    newName: 123456789.dkr.ecr.us-east-1.amazonaws.com/mon-image
    newTag: "v1.0.0"
```

**Étape 4 : Déploiement "Mains Libres"**
1. Commitez et pushez sur `main`.
2. **C'est fini !** L'ApplicationSet ArgoCD détectera instantanément le nouveau répertoire `gitops/apps/mon-nouveau-backend`.
3. Il va provisionner tout seul un namespace Kubernetes portant le nom `mon-nouveau-backend`.
4. Il y déploiera l'intégralité de vos ressources Kubernetes. Vous n'avez jamais eu besoin de créer de fichier de configuration Argo `Applicaton` manuellement.

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
