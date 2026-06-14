#!/bin/bash
set -e

echo "Configuration de Vault pour Kubernetes Auth et External Secrets Operator"

# S'assurer qu'on est connecté au bon cluster
# aws eks update-kubeconfig --region us-east-1 --name gitops-eks-cluster

# 1. Obtenir le token root (A faire manuellement si Vault vient d'être initialisé)
# kubectl exec -n vault vault-0 -- vault operator init
# kubectl exec -n vault vault-0 -- vault operator unseal <KEY>
# export VAULT_TOKEN="<ROOT_TOKEN>"

echo "Activation du moteur KV v2 sur le path 'secret'..."
kubectl exec -n vault vault-0 -- sh -c '
  export VAULT_TOKEN=$VAULT_TOKEN
  vault secrets enable -path=secret kv-v2 || true
'

echo "Activation de lauth Kubernetes..."
kubectl exec -n vault vault-0 -- sh -c '
  export VAULT_TOKEN=$VAULT_TOKEN
  vault auth enable kubernetes || true
  
  # Configuration de lauth kubernetes pour utiliser le service account local
  vault write auth/kubernetes/config \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"
'

echo "Création de la policy pour External Secrets..."
kubectl exec -n vault vault-0 -- sh -c '
  export VAULT_TOKEN=$VAULT_TOKEN
  vault policy write external-secrets - <<EOF
path "secret/data/*" {
  capabilities = ["read"]
}
path "secret/metadata/*" {
  capabilities = ["list"]
}
EOF
'

echo "Création du rôle Vault pour le ServiceAccount external-secrets..."
kubectl exec -n vault vault-0 -- sh -c '
  export VAULT_TOKEN=$VAULT_TOKEN
  vault write auth/kubernetes/role/external-secrets-role \
    bound_service_account_names=external-secrets \
    bound_service_account_namespaces=external-secrets \
    policies=external-secrets \
    ttl=24h
'

echo "Configuration terminée. Vault est prêt à servir des secrets à ESO !"
