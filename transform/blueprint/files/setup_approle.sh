#!/bin/bash

vault auth enable approle

vault write auth/approle/role/payments_app \
    secret_id_ttl=10m \
    token_num_uses=10 \
    token_ttl=20m \
    token_max_ttl=30m \
    secret_id_num_uses=40

output=$(dirname "$0")/../secrets/

# fetch the role-id from vault and parse the response
vault read auth/approle/role/payments_app/role-id -format=json | sed -E -n 's/.*"role_id": "([^"]*).*/\1/p' > ${output}/role_id

# fetch the secret from vault and parse the response
vault write -f auth/approle/role/payments_app/secret-id -format=json | sed -E -n 's/.*"secret_id": "([^"]*).*/\1/p' > ${output}/secret_id