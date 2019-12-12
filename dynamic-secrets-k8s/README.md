# Dynamically generating database credentials with Vault and Kubernetes

Providing and rotating database credentials for your pods has always proved operationally challenging. For optimum security you need unique credentials for each application instance, and these credentials need to be short lived, the access restricted by application function,  and the credentials themselves rotated often. HashiCorp Vault solved this challenge by enabling operators to provide dynamically generated credentials for applications. Once Vault has been configured the life cycle and issue of credentials is automatically handled by Vault.

The new secret injector for Kubernetes allows an operator or developer to inject Vault secrets into a Kubernetes pod using a series of annotations, the following example would automatically inject and manage the life cycle of database credentials into the deployment for our web service.

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-deployment
  labels:
    app: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/agent-inject-secret-db-creds: "database/creds/db-app"
```

The web application can read these credentials from a config file, Vault will automatically rotate them based on a configured TTL, and from an audit perspective every instance of your application has unique credentials assigned to it.

https://github.com/hashicorp/vault-k8s/blob/agent/agent-inject/agent/annotations.go#L12-L99


## How Vault works

Before we look at how Vault and Kubernetes is configured, it is worth quickly recapping how Vault works. There are three main components which are required to use Vault, these are:

* Secrets - either dynamic secrets like database or cloud credentials or static secrets such as API keys or other elements 
* Policy - the method of defining which secrets or operations a user can perform
* Authentication  - the method which a user or application logs into Vault and obtains policy

Using Vault's dynamic secrets engine, it is possible for Vault to generate credentials for your databases on demand. The way that this works is that you configure Vault with static credentials for the database which allow it the ability to generate user credentials. A user or application can then make a request to Vault for database credentials, Vault connects to the database and generates a user account and password with the required access level and returns this to the user. All credentials are created with a time to live, when the TTL expires Vault automatically revokes the credentials in the database.

The Vault Kubernetes integration manages the life cycle of secrets and authentication with Vault automatically for you, it ensures that if the TTL for a secret expires it will automatically renew this for you.

In this blog post we are going to walk through an example of how all this works, you will see how we can provide dynamically generated credentials for a PostgreSQL database to a web application which is running as a deployment in Kubernetes.

## Installing Vault on Kubernetes

TODO: complete this section once method has been decided

```yaml
injector:
  enabled: true
  image: "hashicorp/vault-k8s:0.1.0"
  tls:
    caBundle: ""
    secretName: ""
    certName: cert.pem
    keyName: key.pem
```

Check vault is running...

```
export KUBECONFIG="$HOME/.shipyard/yards/shipyard/kubeconfig.yml"
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=root

demo-vault-kubernetes on  master [?] via 🐹 v1.13.1 at ☸️  default 
➜ vault status
Key             Value
---             -----
Seal Type       shamir
Initialized     true
Sealed          false
Total Shares    1
Threshold       1
Version         1.3.0
Cluster Name    vault-cluster-a34d7889
Cluster ID      09e599a0-75c7-2616-af09-70a03e6ca7a6
HA Enabled      false
```

## Configure Vault Kubernetes Authentication

For Kubernetes Pods to access Vault and to request secrets they need to be authenticated with the Vault server. The sidecar container uses the Kubernetes Service Account Token to authenticate with Vault, if authentication is successful then Vault will return a Vault Token which has specific policy attached to it. To enable the authentication process you need to perform a one time configuration on your new Vault cluster. In order for Vault to verify the Kubernetes Service Token, the authentication backend needs to know the location of the Kubernetes API and needs to have it's own valid credentials to access the API. If you used the Helm chart to install Vault on Kubernetes by default the correct RBAC rules and service account will have been created for the Vault service. Lets see how we can use this information to configure Kubernetes authentication.

[https://www.vaultproject.io/docs/auth/kubernetes.html](https://www.vaultproject.io/docs/auth/kubernetes.html)

The first step is to enable the Kubernetes authentication backend in Vault.

```shell
vault auth enable kubernetes
```

```shell
Success! Enabled kubernetes auth method at: kubernetes/
```

The backend then needs to be configured, to configure the backend we need to provide it with:

* The location of the Kubernetes server
* A valid JWT which can be used to access the K8s API server
* The CA used by the API server to secure it with SSL

### Fetching the ca.crt

When you install Vault using the K8s Helm chart a service account called `vault` is created, this service account has the correct RBAC rules to access the K8s API server in order to validate tokens. You can get the token name using the following `kubectl` command. This will store the token name in an environment variable for use later.

```shell
export TOKEN_NAME=$(kubectl get serviceaccount/vault -o jsonpath='{.secrets[0].name}')
```

Once you have the token name you can obtain the x.509 root certificate which is used in the chain of trust used to enable SSL for the Kubernetes API. This root certificate is stored in the Service Account secret at the `data.ca.crt` path. The following command obtains the CA and writes it to a file `ca.crt`.

```shell
kubectl get secret $TOKEN_NAME -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt
```

The token to authenicate with the Kuberentes API can be obtained using a similar process, this is stored at the `data.token` path in the Service Account secret.

```shell
kubectl get secret $TOKEN_NAME -o jsonpath='{.data.token}' | base64 -d)
```

Finally you can use this information and to configure the Authentication backend, you do this by writing parameters to the configuration path. You need to set the `token_reviewer_jwt` which is the Kubernetes Service Account Token used to access the API server. If you are running Vault on Kubernetes you can set the `kubernetes_host` parameter to the service which the helm chart creates for you. And finally you set the Kubernetes CA which is used to validate the x.509 certificate used to enable TLS on the API endpoint.

You can run the following command to configure the Kubernetes backend.

```shell
vault write auth/kubernetes/config \
    token_reviewer_jwt="$(kubectl get secret $TOKEN_NAME -o jsonpath='{.data.token}' | base64 -d)" \
    kubernetes_host="https://kubernetes:443" \
    kubernetes_ca_cert=@ca.crt
```

```shell
Success! Data written to: auth/kubernetes/config
```

This configuration is only necessary when setting up a new Kubernetes cluster to work with Vault and is a once only operation.

## Deploy a Postgres database to Kubernetes

Now you have your Kubernetes and your Vault cluster configured, lets deploy our PostgreSQL database. For convenience we are going to deploy this to Kubernetes, however; this is not necessary, you could also use a database which is a managed cloud offering or which is running in a virtual machine or physical hardware.

Lets deploy the database using the example from the examples repo, this will create a deployment in your Kubernetes cluster and a service called `postgres` which points to the deployment.

```yaml
kubectl apply -f config/postgres.yml
```

Next we configure Vault to work with the new database.

## Configuring Postgres in Vault

The way that dynamic secrets for databases work with vault is that you have a database backend which is configured for a specific database instance and then multiple roles for that database. A role defines what access level the dynamic credentials created through Vault will have. For example you can create a role which allows an application to read from a specific table, a role which allows an application to write to a specific table, or a role for DB administrators which allows full access to the database.

The first step is to enable the database backend.

```shell
vault secrets enable database
```

Then the backend can be configured, each different type of database secret engine requires slightly different configuration parameters but the workflow for configuration, creating roles and generating credentials is exactly the same.  For PostgreSQL we are going to tell Vault that we want to use the `postgresql-database-plugin`. And that the roles which can use this configuration defined by the `allowed_roles` parameter is everything. Since the connection relates to a specific database on the PostgreSQL server we can be very granular with this configuration. You need to define the connection string by setting the `connection_url` parameter, this is in the form of a standard connection string. Notice however that we are not hard coding the `username` and `password` in the connection string. Instead we are using the template variables `{{username}}` and `{{password}}`, we then specify the username and password as parameters. The reason we are doing this is that Vault has the capability to rotate the root credentials provided in this configuration, with this capability no trace of the route credentials can be left lying round.

We are going to write this to the path `database/config` with the name `web-db`.

```
vault write database/config/web-db \
    plugin_name=postgresql-database-plugin \
    allowed_roles="*" \
    connection_url="postgresql://{{username}}:{{password}}@postgres:5432/wizard?sslmode=disable" \
    username="postgres" \
    password="password"
```

Once the database has been configured you can create a role, the `db_name` refers to the name of the configuration which was set in the previous step.  You then need to configure the `creation_statements`. When a user or application requests credentials, Vault will execute the SQL statement defined in the `creation_statements` parameter. In this example we are going to create a role in the database `wizard` which allows select access to all tables. The `creation_statements` are PostgreSQL standard SQL statements, again template variables are used, `{{name}}`, `{{password}}`, and `{{expiration}}` will be dynamically substituted by Vault when the statement is executed.  To revoke credentials once the time to live has elapsed Vault also allows you to define `revocation_statements`, in the example below we are disabling the Login once the TTL expires. We could also do additional things like terminating any running processes, again we are using PostgreSQL compliant SQL so the possibilities are limitless.  Finally we have two parameters `default_ttl` and `max_ttl`. `default_ttl` defines the lease length for a secret, this is set to `1h`, this means you need to renew the lease on a secret every hour. A lease tells Vault that you are still using the credentials and that it should not automatically revoke them. With the Kubernetes integration for Vault this lease will be automatically managed for you. As long as the pod is running the secret will be kept alive, however once the pod is destroyed Vault will automatically revoke the credentials once the lease expires. The benefit to this approach is that even if the credentials leak, they will be cleaned up as soon as possible. The final parameter is `max_ttl`, unlike the `default_ttl` which defines the renewal interval `max_ttl` defines the maximum duration which credentials can exist. In this instance we are setting a value of `24hrs`, after this period the credentials can not be renewed an more and Vault will automatically revoke them. The Vault Kubernetes integration will automatically do this for you however you do need to handle the process in your application to read the new credentials and reload any database connections.

To write the role again you can use the `vault write` command:

```
vault write database/roles/db-app \
    db_name=web-db \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    revocation_statements="ALTER ROLE \"{{name}}\" NOLOGIN;"\
    default_ttl="1h" \
    max_ttl="24h"
```

Test this works

```
vault read database/creds/db-app

Key                Value
---                -----
lease_id           database/creds/db-app/TFn7HdQSsi1vlsZAFYNLVVap
lease_duration     1h
lease_renewable    true
password           A1a-H1CV9n5ckU4Rn3ai
username           v-token-db-app-xAtDf94wzrp1yvQaUZtE-1575906706
```


## Create the policy which allows access to the DB role

```
vault policy write web ./config/policy.hcl 
Success! Uploaded policy: web
```

## Create the mapping between K8s service account and the vault policy

```
vault write auth/kubernetes/role/web \
    bound_service_account_names=web \
    bound_service_account_namespaces=default \
    policies=web \
    ttl=1h
```


## Deploy our application

```
kubectl apply -f ./config/application.yml
```

Check the output

```
kubectl exec -it web-deployment-5fcb454bc9-xd2gm -c web cat /vault/secrets/db-creds | jq
{
  "db_connection": "postgresql://v-kubernet-db-app-Eui3d4uc0wUswYLGU7g8-1575910648:A1a-GpbyTKdHMinXMxAo@postgres:5432/wizard"
}
```

