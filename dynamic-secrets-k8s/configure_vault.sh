#!/bin/bash

# Enable and configure Kubernetes Authentication
vault auth enable kubernetes

kubectl exec $(kubectl get pods --selector "app.kubernetes.io/instance=vault,component=server" -o jsonpath="{.items[0].metadata.name}") -c vault -- \
  sh -c ' \
    vault write auth/kubernetes/config \
       token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
       kubernetes_host=https://${KUBERNETES_PORT_443_TCP_ADDR}:443 \
       kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'

# Enable and configure PostgresSQL Dynamic secrets
vault secrets enable database

vault write database/config/wizard \
    plugin_name=postgresql-database-plugin \
    verify_connection=false \
    allowed_roles="*" \
    connection_url="postgresql://{{username}}:{{password}}@postgres:5432/wizard?sslmode=disable" \
    username="postgres" \
    password="password"

# Rotate the database root password
vault write --force database/rotate-root/wizard

# Create a role allowing credentials to be created with access for all tables in the DB
vault write database/roles/db-app \
    db_name=wizard \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    revocation_statements="ALTER ROLE \"{{name}}\" NOLOGIN;"\
    default_ttl="1h" \
    max_ttl="24h"

# Write the policy to allow read access to the role
vault policy write web-dynamic ./config/web-policy.hcl

# Assign the policy to users who authenticate with Kubernetes service accounts called web
vault write auth/kubernetes/role/web \
    bound_service_account_names=web \
    bound_service_account_namespaces=default \
    policies=web-dynamic \
    ttl=1h
