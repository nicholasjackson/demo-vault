# Static Secrets with Vault and Kubernetes 

README coming soon, 

## Enable and configure Kubernetes Authentication

```shell
vault auth enable kubernetes

kubectl exec $(kubectl get pods --selector "app.kubernetes.io/instance=vault,component=server" -o jsonpath="{.items[0].metadata.name}") -c vault -- \
  sh -c ' \
    vault write auth/kubernetes/config \
       token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
       kubernetes_host=https://${KUBERNETES_PORT_443_TCP_ADDR}:443 \
       kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'
```

## Write a secret to the Vault

```shell
vault kv put secret/web api_key=abc123fd
```

## Write policy allowing read access to that secret

```shell
vault policy write web-static ./config/web-policy.hcl
```

## Assign the policy to users who authenticate with Kubernetes service accounts called web

```shell
vault write auth/kubernetes/role/web \
    bound_service_account_names=web \
    bound_service_account_namespaces=default \
    policies=web-static \
    ttl=1h
```

## Apply the Config with annotations to inject secrets

```yaml
annotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/agent-inject-secret-web: secret/data/web
  vault.hashicorp.com/agent-inject-template-web: |
    {
    {{ with secret "secret/data/web" -}}
      "api_key": "{{ .Data.data.api_key }}"
    {{- end }}
    }
  vault.hashicorp.com/role: "web"
```

## Check the result

```shell
kubectl exec -it $(kubectl get pods --selector "app=web" -o jsonpath="{.items[0].metadata.name}") -c web -- cat /vault/secrets/web
```