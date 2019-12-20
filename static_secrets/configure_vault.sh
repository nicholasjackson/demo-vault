#!/bin/bash

# Enable and configure Kubernetes Authentication
vault auth enable kubernetes

kubectl exec $(kubectl get pods --selector "app.kubernetes.io/instance=vault,component=server" -o jsonpath="{.items[0].metadata.name}") -c vault -- \
  sh -c ' \
    vault write auth/kubernetes/config \
       token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
       kubernetes_host=https://${KUBERNETES_PORT_443_TCP_ADDR}:443 \
       kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'

# Write a secret to the database
vault kv put secret/web api_key=abc123fd

# Write policy allowing read access to that secret
vault policy write web-static ./config/web-policy.hcl

# Assign the policy to users who authenticate with Kubernetes service accounts called web
vault write auth/kubernetes/role/web \
    bound_service_account_names=web \
    bound_service_account_namespaces=default \
    policies=web-static \
    ttl=1h