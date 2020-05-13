---
title: Vault Transform Example
author: Nic Jackson
slug: vault_transform
env:
  - VAULT_ADDR=http://localhost:8200
  - VAULT_TOKEN=root
---

# Environment Variables
To interact with the Vault server using the Vault CLI, set the following environment variables:

```shell
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="root"
```

# Vault Server Shell
If you do not have the Vault CLI installed, you can use Shipyard to create an interactive shell 
on the Vault server.

```shell
shipyard exec container.vault
```

# Using the Transform Secrets engine

After the Vault container starts the `transform` is automatically 
configured using the script `./files/setup_vault.sh`. This sets up the
role and transform values.

To write values using the `transform` engine:

```shell
vault write transform/encode/payments value=1111-2222-3333-4444

Key              Value

encoded_value    9300-3376-4943-8903
```

To read values using the `transform` secrets:

```shell
vault write transform/decode/payments value=9300-3376-4943-8903
Key              Value

decoded_value    1111-2222-3333-4444
```