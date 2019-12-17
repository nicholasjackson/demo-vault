#!/bin/bash

vault auth enable kubernetes

export TOKEN_NAME=$(kubectl get serviceaccount/vault -o jsonpath='{.secrets[0].name}')
kubectl get secret $TOKEN_NAME -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt
kubectl get secret $TOKEN_NAME -o jsonpath='{.data.token}' | base64 -d

vault write auth/kubernetes/config \
    token_reviewer_jwt="$(kubectl get secret $TOKEN_NAME -o jsonpath='{.data.token}' | base64 -d)" \
    kubernetes_host="https://kubernetes:443" \
    kubernetes_ca_cert=@ca.crt

vault secrets enable database

vault write database/config/web-db \
    plugin_name=postgresql-database-plugin \
    verify_connection=false \
    allowed_roles="*" \
    connection_url="postgresql://{{username}}:{{password}}@postgres:5432/wizard?sslmode=disable" \
    username="postgres" \
    password="password"

vault write database/roles/db-app \
    db_name=web-db \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    revocation_statements="ALTER ROLE \"{{name}}\" NOLOGIN;"\
    default_ttl="1h" \
    max_ttl="24h"

vault policy write web ./config/web-policy.hcl

vault write auth/kubernetes/role/web \
    bound_service_account_names=web \
    bound_service_account_namespaces=default \
    policies=web \
    ttl=1h