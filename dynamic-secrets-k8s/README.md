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
```

![](./images/1_status.svg)

## Configure Vault Kubernetes Authentication

For Kubernetes Pods to access Vault and to request secrets they need to be authenticated with the Vault server. The sidecar container uses the Kubernetes Service Account Token to authenticate with Vault, if authentication is successful then Vault will return a Vault Token which has specific policy attached to it. To enable the authentication process you need to perform a one time configuration on your new Vault cluster. In order for Vault to verify the Kubernetes Service Token, the authentication backend needs to know the location of the Kubernetes API and needs to have it's own valid credentials to access the API. If you used the Helm chart to install Vault on Kubernetes by default the correct RBAC rules and service account will have been created for the Vault service. Lets see how we can use this information to configure Kubernetes authentication.

[https://www.vaultproject.io/docs/auth/kubernetes.html](https://www.vaultproject.io/docs/auth/kubernetes.html)

The first step is to enable the Kubernetes authentication backend in Vault.

```shell
vault auth enable kubernetes
```

![](./images/2_enable.svg)

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
kubectl get secret $TOKEN_NAME -o jsonpath='{.data.token}' | base64 -d
```

Finally you can use this information and to configure the Authentication backend, you do this by writing parameters to the configuration path. You need to set the `token_reviewer_jwt` which is the Kubernetes Service Account Token used to access the API server. If you are running Vault on Kubernetes you can set the `kubernetes_host` parameter to the service which the helm chart creates for you. And finally you set the Kubernetes CA which is used to validate the x.509 certificate used to enable TLS on the API endpoint.

You can run the following command to configure the Kubernetes backend.

```shell
vault write auth/kubernetes/config \
    token_reviewer_jwt="$(kubectl get secret $TOKEN_NAME -o jsonpath='{.data.token}' | base64 -d)" \
    kubernetes_host="https://kubernetes:443" \
    kubernetes_ca_cert=@ca.crt
```

![](images/3_configure.svg)

This configuration is only necessary when setting up a new Kubernetes cluster to work with Vault and is a once only operation.

## Deploy a Postgres database to Kubernetes

Now you have your Kubernetes and your Vault cluster configured, lets deploy our PostgreSQL database. For convenience we are going to deploy this to Kubernetes, however; this is not necessary, you could also use a database which is a managed cloud offering or which is running in a virtual machine or physical hardware.

Lets deploy the database using the example from the examples repo, this will create a deployment in your Kubernetes cluster and a service called `postgres` which points to the deployment.

```yaml
kubectl apply -f config/postgres.yml
```

![](images/4_postgresql.svg)

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

```bash
vault write database/roles/db-app \
    db_name=web-db \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    revocation_statements="ALTER ROLE \"{{name}}\" NOLOGIN;"\
    default_ttl="1h" \
    max_ttl="24h"
```

You can manually check that this is working by manually requesting Vault creates credentials for you, you will see some output similar to that below. Note that both the username and the password are randomly generated and that the initial lease duration corresponds to the `default_ttl`.

```bash
vault read database/creds/db-app
```

![](./images/5_pg_configure.svg)

## Creating a policy to allows access to the DB role

Permissions to access secrets in Vault are controlled through policy, in order to allow our Kubernetes web service to create credentials you need to define a policy in Vault which allows `read` access to the secrets. The secrets created in the previous step have a path with the convention `database/creds/[role]`, this gives you a path of `databse/creds/db-app`. You also need to define the capabilities, which are granted for the path, to create dynamic database secrets only the `read` capability is required.

```ruby
path "database/creds/db-app" {
  capabilities = ["read"]
}
```

Once you have created the policy, you can write it to vault using the following command.

```shell
vault policy write web ./config/web-policy.hcl 
```

![](./images/6_policy.svg)

## Create the mapping between K8s service account and the vault policy

The Vault sidecar is going to use the Service Account Token allocated to the pod for authentication to Vault, Vault will exchange this for a Vault Token which is assigned a number of policies. To create this mapping you need to create a `role` in the Kubernetes Auth Method. To do this you write config to `auth\kubernetes/role/[name]`. To assign the policy `web` when authenticating with the service account `web` in the namespace `default`, you can write the following configuration. 

`bound_service_account_names` are the names of the service accounts provided as a comma separated list which can use this role.  
`bound_service_account_namesapces` are the allowed namespaces for the service accounts.  
`policies` are the policies which you would like to attach to the token.  
`ttl` is the time to live for the Vault token returned from a successful authentication.

```bash
vault write auth/kubernetes/role/web \
    bound_service_account_names=web \
    bound_service_account_namespaces=default \
    policies=web \
    ttl=1h
```

![](./images/7_mapping.svg)


## Configuring a deployment to inject secrets

Now the Vault configuration is complete, lets see how we can inject the secrets into our application. The first thing we need to do is ensure that there is a service account which matches the name in the role you configured in the previous step.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: web
automountServiceAccountToken: true
```

We can then configure the deployment to automatically inject the database credentials, this is done through annotations. The first annotation we are going to add tells Vault to automatically inject a sidecar to manage secrets into the deployment.

`vault.hashicorp.com/agent-inject: "true"`

You can then tell it which secrets you would like to inject, the below annotation will inject the dynamic database credentials which were configured earlier.

`vault.hashicorp.com/agent-inject-secret-db-creds: "database/creds/db-app"`

All secrets are injected by default at `/vault/secrets/[name]`, for database credentials the default format would be:

```
username: random-user-name
password: random-password
```

To control the format so that the application can read it in a native format you can use the annotation `vault.hashicorp.com/agent-inject-template-[filename]`, to define a custom template. This template is based on the Consul Template format [https://github.com/hashicorp/consul-template#secret](https://github.com/hashicorp/consul-template#secret). The start block `[[- with secret "database/creds/db-app" -]]`, allows you to select a secret from `database/cred/db-app` and make its data available inside the block. The next line contains `[[ .Data.username ]]` and `[[ .Data.password ]]`, these are template variables which when processed will container the database credentials username and password. Finally you close the block with `[[- end ]]`. 

```yaml
vault.hashicorp.com/agent-inject-template-db-creds: |
  {
  [[- with secret "database/creds/db-app" -]]
  "db_connection": "postgresql://[[ .Data.username ]]:[[ .Data.password ]]@postgres:5432/wizard"
  [[- end ]]
  }
```

If you remove the template elements the template elements the output would look something like: `{"db_connection": "postgresql://username:password@postgres:5432/wizard"}`.  Templates can contain more than one secret so regardless of the configuration format that your application needs you can define this using the flexible templating language.

Finaly you specify the role which will be used by the sidecar authentication, this is the role you created earlier when configuring Vault.

`vault.hashicorp.com/role: "web"`

Putting all of this together you get a deployment which looks something like the following example:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-deployment
  labels:
    app: web
spec:
  replicas: 2
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
        vault.hashicorp.com/agent-inject-template-db-creds: |
          {
          [[- with secret "database/creds/db-app" -]]
          "db_connection": "postgresql://[[ .Data.username ]]:[[ .Data.password ]]@postgres:5432/wizard"
          [[- end ]]
          }
        vault.hashicorp.com/role: "web"
        vault.hashicorp.com/service: "http://vault"
    spec:
      serviceAccountName: web
      containers:
        - name: web
          image: nicholasjackson/fake-service:v0.7.3
```

This can be then deployed in the usual Kubernetes way.

```bash
kubectl apply -f ./config/web.yml
```

The injector will automatically modify your deployment adding a `vault-agent` container which has been configured to authenticate with the Vault server and to write the secrets into your pod.

This can been seen by looking at the file `/vault/secrets/db-creds` in the web pod, if you run the following command you will see the secrets which have been written as a JSON file. Whenever the secrets expire Vault will automatically re-generate this file, your application can watch for changes reloading the configuration as necessary.

```
kubectl exec -it $(kubectl get pods --selector "app=web" -o jsonpath="{.items[0].metadata.name}")\
 -c web cat /vault/secrets/db-creds
```

Since the deployment contains two pods you can run the following command to look at the second pod, you will see that each pod has been allocated unique databse credentials.

```
kubectl exec -it $(kubectl get pods --selector "app=web" -o jsonpath="{.items[1].metadata.name}")\
 -c web cat /vault/secrets/db-creds
```

`termtosvg -t window_frame_powershell -g 102x20 -D 4 ./images/8_secrets.svg`

![](./images/8_secrets.svg)


## Summary

In this post we have walked through all of the steps required to configure Vault and Kubernetes in order to provide dynamic database secrets to our applications. Vault is an incredibly powerful tool and is not limited to PostgreSQL as showing in this post.