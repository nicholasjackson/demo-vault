# Dynamic Database Credentials with Vault and Kubernetes

Providing database credentials for your Kubernetes applications has always proved operationally challenging. For optimum security, we ideally need to implement the following requirements for database credentials:

* Each Kubernetes pod should have a unique set of credentials
* Credentials should be disabled or deleted when a pod terminates
* Credentials should be short-lived and rotated frequently
* Access should be restricted by application function, a system which only needs to read a specific table, should have database access which grants this particular purpose

While these requirements are essential for reducing the blast radius in the event of an attack, they are operationally challenging. The reality is that without automation, it is impossible to satisfy them. HashiCorp Vault solves this problem by enabling operators to provide dynamically generated credentials for applications. Vault manages the lifecycle of credentials, rotating and revoking as required.

In this blog post, we will look at how the Vault integration for Kubernetes allows an operator or developer to use metadata annotations to inject dynamically generated database secrets into a Kubernetes pod. The integration automatically handles all the authentication with Vault and the management of the secrets, the application just reads the secrets from the filesystem.

## Contents
- [Dynamic Database Credentials with Vault and Kubernetes](#dynamic-database-credentials-with-vault-and-kubernetes)
  - [Contents](#contents)
  - [Summary of Integration Workflow](#summary-of-integration-workflow)
  - [Prerequisites](#prerequisites)
  - [Introduction to Vault](#introduction-to-vault)
    - [Secrets](#secrets)
    - [Authentication](#authentication)
    - [Policy](#policy)
  - [Secrets - Configuring dynamic secrets for PostgreSQL](#secrets---configuring-dynamic-secrets-for-postgresql)
    - [Enable the PostgreSQL secrets backend](#enable-the-postgresql-secrets-backend)
    - [Creating database roles](#creating-database-roles)
    - [Creating database connections](#creating-database-connections)
    - [Rotating the root credentials](#rotating-the-root-credentials)
  - [Authentication - Configuring Kubernetes Authentication in Vault](#authentication---configuring-kubernetes-authentication-in-vault)
  - [Policy - Creating policy to allow access to secrets](#policy---creating-policy-to-allow-access-to-secrets)
    - [Assigning Vault policy to Kubernetes Service Accounts](#assigning-vault-policy-to-kubernetes-service-accounts)
  - [Injecting secrets into Kubernetes Deployments](#injecting-secrets-into-kubernetes-deployments)
  - [Summary](#summary)

## Summary of Integration Workflow
When a new deployment is submitted to Kubernetes, a mutating webhook modifies the deployment, injects a Vault sidecar. This sidecar manages the authentication to Vault and the retrieval of secrets. The retrieved secrets are written to a pod volume mount that your application can read.

For example, we can use Vault to dynamically generate database credentials for a PostgreSQL database. Adding the annotations shown in the following example automatically inject secrets controlled by the db-creds role into the pod.

```yaml
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

https://www.vaultproject.io/docs/platform/k8s/injector/index.html

By convention Vault will inject these at the path `/vault/secrets/<secret name>`, the following snippet shows an example of this file.

```shell
username: v-kubernet-db-app-QDTv8wn6oGze6aGxuYbQ-1576778182
password: A1a-7kHXqX0jdh8ys74H
```

Before we will walk through the process of deploying and configuring Vault in a Kubernetes cluster and learn how to inject PostgreSQL credentials into a Kubernetes deployment. Let's introduce some HashiCorp Vault’s core concepts.


## Prerequisites

If you do not have access to a Kubernetes cluster with Vault and would like to try the features in this blog, you can use `Shipyard` to create a local Docker-based Kubernetes cluster with Vault pre-installed.

```
curl https://shipyard.demo.gs/vault | bash
```

All the example configuration mentioned in this post can be downloaded at:

```
http://github.com/nicholasjackson/vault-demo
```

## Introduction to Vault

Vault is built around three main concepts:

* Secrets
* Authentication
* Policy

In this section, we review how these concepts work in Vault.

![](https://www.datocms-assets.com/2885/1576778376-vault-workflow-illustration-policy.png)

### Secrets
You can have static secrets like an API key or a credit card number or dynamic secrets like auto-generated cloud or database credentials. Vault generates dynamic secrets on-demand, while you receive static secrets already pre-defined.

With static secrets, you must create and manage the lifecycle of the secret. For example, you could store an email account password in Vault but you need to ensure that it is periodically changed.

With dynamic secrets, you delegate the responsibility to Vault for creating and managing the lifecycle of a secret. For example, you give Vault the root credentials for your PostgreSQL database, granting it access to create credentials on your behalf. When you want to log into the database, you ask Vault for credentials. Vault makes a connection to the database and generates a set of restricted access credentials. These are not permanent but leased. Vault manages the lifecycle, automatically rotating the password and revoking the access when they are no longer required.

One of the critical features of defense in depth is rotating credentials. In the event of a breach, credentials with a strict time to live (TTL) can dramatically reduce the blast radius.

![](https://www.datocms-assets.com/2885/1576778435-vault-db.png)

### Authentication
To access secrets in Vault, you need to be authenticated; authentication is in the form of pluggable backends. For example, you can use a Kubernetes Service Account token to authenticate to Vault. For human access, you could use something like GitHub tokens. In both of these instances, Vault does not directly store the credentials; instead, it uses a trusted third party to validate the credentials.  With Kubernetes Service Account tokens, when an application attempts to authenticate with Vault, Vault makes a call to the Kubernetes API to ensure the validity of the token. If the token is valid, it returns an internally managed Vault Token, used by the application for future requests.

![](https://www.datocms-assets.com/2885/1576778470-vault-k8s-auth.png)

### Policy
Policy ties together secrets and authentication by defining which secrets and what administrative operations an authenticated user can perform. For example, an operator may have a policy which allows them to configure secrets for a PostgreSQL database, but not generate credentials. An application may have permission to create credentials but not configure the backend. Vault policy allows you correctly separate responsibility based on role.

```hcl
# policy allowing creation and configuration of databases and roles
path “database/roles/*” {
  capabilities = [“create”, “read”, “update”, “delete”, “list”] 
}

path “database/config/*” {
  capabilities = [“create”, “read”, “update”, “delete”, “list”] 
}

# policy allowing credentials for the wizard database to be created 
path “database/creds/wizard” {
  capabilities = [“read”] 
}
```

## Secrets - Configuring dynamic secrets for PostgreSQL

Before you can configure Vault, you need a database. In this example, you will deploy the database to Kubernetes for convenience. You could also use a database from a managed cloud offering or running in a virtual machine or on physical hardware.

Let's deploy the database using the example from the examples repo and create a deployment in your Kubernetes cluster. The example file also creates a  service called `postgres` which points to the pod created by the deployment.

```yaml
kubectl apply -f config/postgres.yml
```

![](https://www.datocms-assets.com/2885/1576778968-1deploydb.svg)

While this example focuses on the configuration for PostgreSQL,  the workflow for configuration, creating roles, and generating credentials applies to any database.

### Enable the PostgreSQL secrets backend

Before configuring connections and roles, first you need to enable the database backend.

```shell
vault secrets enable database
```

Once the secrets engine has been enabled you can start to create roles.
### Creating database roles

Role configuration controls the tables to which a user has access and the lifecycle of the credentials. Often multiple roles are created for each connection. For example, an application may require read access on the products table but a human operator may require write access to the users table. 

You create roles by writing configuration to the path `database/roles/<role name>.` Let's take a look at the parameters in more depth.

The `db_name` parameter refers to the name of the database connection; we are going to configure the connection for the database in the next step. For now, you can set the value `wizard,` as this will be the name of the connection when created.

When a user or application requests credentials, Vault will execute the SQL statement defined in the `creation_statements` parameter. This example, creates a role in the database `wizard` which allows select access to all tables. 

The `creation_statements` are PostgreSQL standard SQL statements. SQL statements can contain template variables which are dynamically substituted at runtime. If you look at the create SQL statement below, you will see three template variables `{{name}}`, `{{password}}` and `{{expiration}}`:

* `{{name}}` is the randomly generated username that Vault will generate
* `{{password}}` is the randomly generated password
* `{{expiration}}` is the data after which the credentials are no longer valid

```sql
CREATE ROLE '{{name}}' WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; 
GRANT SELECT ON ALL TABLES IN SCHEMA public TO "{{name}}";
```

When Vault runs this statement it will replace the template variables with uniquely generated values. For example, the previous statement would become:

```sql
CREATE ROLE 'abc3412vsdfsfd' WITH LOGIN PASSWORD 'sfklasdfj234234fdsfdsd' VALID UNTIL '2019-12-31 23:59:59'; 
GRANT SELECT ON ALL TABLES IN SCHEMA public TO "'abc3412vsdfsfd'";
```

When the TTL for a secret expires Vault runs the SQL statement defined in the `revocation_statements` parameter. The following statement would disable the PostgreSQL user which is defined by the template variable `{{name}}`.

```sql
ALTER ROLE "{{name}}" NOLOGIN;
```

The final two parameters are `default_ttl` and `max_ttl.` 

`default_ttl` defines the lease length for a secret; this is set to `1h`; this means you need to renew the lease on a secret every hour.

A lease tells Vault that you are still using the credentials and that it should not automatically revoke them. With the Kubernetes integration for Vault, Vault manages the lease for us. As long as the pod is running, your application can use the secret. However, once the pod terminates, Vault automatically revokes the credentials once the lease expires.

The benefit of lease credentials is that they are automatically revoked after a predetermined period of time, if the credentials leak, the blast radius is dramatically reduced as the period of usefulness for credentials is limited. When a human operator is managing credentials they must manually be revoked, that is assuming the operator is aware of the leak, often they are not until it is too late.

`max_ttl`, specifies the maximum duration which credentials can exist regardless of the number of times a lease is renewed. In this example, `max_ttl` has a value of `24hrs`,after this period, the credentials can not be renewed and Vault automatically revokes them. 

The Vault Kubernetes integration automatically renews the credentials. The application handles the renewal process, reading the new credentials, and reloading any database connections. To avoid credentials being revoked while in use, the sidecar process always renews credentials before they expire. This way, the application can safely close any open database connections before rolling over to the new credentials received by the sidecar process.

Let’s put all of this together and write the role to Vault:

```bash
vault write database/roles/db-app \
    db_name=wizard \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    revocation_statements="ALTER ROLE \"{{name}}\" NOLOGIN;"\
    default_ttl="1h" \
    max_ttl="24h"
```

![](https://www.datocms-assets.com/2885/1576779138-2createrole.svg)

### Creating database connections
A connection manages the root access for a database. For example, your PostgreSQL server has the database `wizard` on it. The connection in Vault is the configuration to connect to and authenticate with that database. Like a role, you configure several parameters.

The `plugin_name` parameter configures which database plugin we would like to use. This example is using a PostgreSQL database so you use `postgresql-database-plugin`

You also need to define which roles can use this connection with the `allowed_roles` parameter; this will be set to the name of the role created in the previous step, `wizard.`

For Vault to connect to the database, you define a standard connection string by setting the `connection_url` parameter. Rather than hardcoding the `username` and `password` in the connection string, you must use template variables to enable Vault's root credential rotation feature. This feature allows Vault to automatically rotate the root credentials for a database.

```
postgresql://{{username}}:{{password}}@postgres:5432/wizard?sslmode=disable"
```

Finally, you define `username` and `password` the initial credentials which Vault will use when connecting to your PostgreSQL database.

You apply this configuration with a `vault write` command. The path this time is going to be `database/config/<connection name>`:

```shell
vault write database/config/wizard \
    plugin_name=postgresql-database-plugin \
    allowed_roles="*" \
    connection_url="postgresql://{{username}}:{{password}}@postgres:5432/wizard?sslmode=disable" \
    username="postgres" \
    password="password"
```

![](https://www.datocms-assets.com/2885/1576779279-3createconnection.svg)

### Rotating the root credentials
When you create a new database, you need to create root credentials for configuring additional users. In the example, you use the `POSTGRES_PASSWORD` environment variable your deployment definition to set the database password on initialization.

```yaml
env:
  - name: POSTGRES_PASSWORD
    value: password
```

Since Vault can manage credential creation for both humans and applications, you no longer need the original password. Vaults root rotation can automatically change this password to one only Vault can use.

When Vault rotates root credentials, it connects to the database using its existing root credentials. It then generates a new password for the configured user. Vault saves the password but you cannot retrieve it. This process removes the paper trail associated with the original password. Should you need to access the database then it is always possible to ask Vault to generate credentials. Run the following command to rotate the root credentials:

```shell
vault write --force /database/rotate-root/wizard
```

After running this command, you can check that Vault has rotated the credentials by trying to login using `psql` using the original credentials:

```shell
kubectl exec -it $(kubectl get pods --selector "app=postgres" -o jsonpath="{.items[0].metadata.name}") -c postgres -- bash -c 'PGPASSWORD=password psql -U postgres'
```

Finally you can test the generation of credentials for your application by using the `vault read database/creds/<role>` command. 

```shell
vault read database/creds/db-app
```

If you look at the output from this command, you see a randomly generated `username` and `password`and a `lease` equal to the `default_ttl` you configured when creating the role.

![](https://www.datocms-assets.com/2885/1576779576-4rotatecreds.svg)

## Authentication - Configuring Kubernetes Authentication in Vault
To enable applications to authenticate with Vault, we need to enable the Kubernetes authentication backend. This backend allows the application to obtain a Vault token by authenticating with Vault using a Kubernetes Service Account token. The Vault injector automatically manages the process of authentication for you, but you do need to configure Vault for this process to work.

For Vault to verify the Kubernetes Service Account token, the authentication backend needs to know the location of the Kubernetes API and needs to have valid credentials to access the API. You must ensure the Vault cluster uses the correct Kubernetes RBAC rules and service account. The Vault Helm chart and [Vault documentation](https://www.vaultproject.io/docs/auth/kubernetes.html) outlines the proper permissions.

The first step is to enable the Kubernetes authentication backend in Vault.

```shell
vault auth enable kubernetes
```

Like the database backend, authentication backends also need to be configured, let’s look at the parameters required for this configuration.

The `token_reviewer` parameter is set to a value Kubernetes Service Account token. Vault uses this token to authenticate itself when making calls with the Kubernetes API.

When making a call to the API Vault validates the TLS certificates used by the Kubernetes API. To perform this validation the CA certificate for the Kubernetes server is needed. You set `kubernetes_ca_cert` parameter with the contents of this certificate.

Finally the `kubernetes_host` parameter needs to be set to the address for the Kubernetes API. Vault will use the value of this parameter when making HTTP calls to the API.

If you are running Vault on Kubernetes you can use the following command to set this configuration. The Vault server pod already has a service account token with this information, so we can run a `kubectl exec` to execute the configure command directly in the pod:

```
kubectl exec $(kubectl get pods --selector "app.kubernetes.io/instance=vault,component=server" -o jsonpath="{.items[0].metadata.name}") -c vault -- \
  sh -c ' \
    vault write auth/kubernetes/config \
       token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
       kubernetes_host=https://${KUBERNETES_PORT_443_TCP_ADDR}:443 \
       kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'
```

This configuration is only necessary when setting up a new Kubernetes cluster to work with Vault and only needs to be completed once.

![](https://www.datocms-assets.com/2885/1576779679-5authentication.svg)

## Policy - Creating policy to allow access to secrets
Policy controls the permissions to access secrets in Vault. In order for our application to create database credentials, you need to define a policy in Vault to allow `read` access to the secret.

Vault applies policy based on the `path` of the secret. For example, the path for database secrets is `database/creds/<role>.` For the role created earlier, you can access the database secret at  `database/creds/db-app`. 

You also need to define capabilities (create, read, update, delete), or access level for the path. Creation of dynamic secrets requires the `read` capability.

```ruby
path "database/creds/db-app" {
  capabilities = ["read"]
}
```

If you have checked out the example code, this policy can be found at `./config/webpolicy.hcl`. You can write the policy to Vault using the `vault policy write <name> <location>` command. Run the following command which will create a policy named `web` from the example file.

```shell
vault policy write web ./config/web-policy.hcl
```

### Assigning Vault policy to Kubernetes Service Accounts 
The Vault secret injector uses the Service Account Token allocated to the pod for authentication to Vault. Vault exchanges this for a Vault Token, which has policies assigned. 

![](https://www.datocms-assets.com/2885/1576778470-vault-k8s-auth.png)

To create this mapping, you need to create a `role` in the Kubernetes authentication you configured earlier. This is done by writing configuration to `auth\kubernetes/role/<name>`. To assign the policy `web` when a pod authenticates using the service account `web,` in the namespace `default,` you need to set the following parameters:

* `bound_service_account_names` are the names of the service accounts provided as a comma-separated list that can use this role.

* `bound_service_account_namesapces` are the allowed namespaces for the service accounts.

* `policies` are the policies that you would like to attach to the token.

* `ttl` is the time to live for the Vault token returned from successful authentication.

The full command can be seen in the following snippet. Run this in your terminal to create the role.

```bash
vault write auth/kubernetes/role/web \
    bound_service_account_names=web \
    bound_service_account_namespaces=default \
    policies=web \
    ttl=1h
```

![](https://www.datocms-assets.com/2885/1576781231-6policy.svg)

## Injecting secrets into Kubernetes Deployments
Now the Vault configuration is complete, you can inject the secrets into the application.

First, you need to match the name of a Kubernetes Service Account to the name of the role you configured in the previous step.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: web
automountServiceAccountToken: true
```

You can then configure the deployment to inject the database credentials automatically with an annotation. The first annotation you need to add tells Vault to inject a sidecar to manage secrets into the deployment automatically.

`vault.hashicorp.com/agent-inject: "true"`

You can then tell it which secrets you would like to inject, such as the database credentials which were configured earlier.

`vault.hashicorp.com/agent-inject-secret-db-creds: "database/creds/db-app"`

The injector mounts the secrets in the pod  at `/vault/secrets/<name>`. For database credentials, the default format would be:

```
username: random-user-name
password: random-password
```

To control the format so that the application can read it in a native format, you can use the annotation `vault.hashicorp.com/agent-inject-template-[filename],` to define a custom template. This template uses Consul Template format: [https://github.com/hashicorp/consul-template#secret](https://github.com/hashicorp/consul-template#secret). 

The following annotation example would allow us to use this templating feature to generate a JSON formatted config file which contains a connection string suitable for Go's standard SQL package. 

```yaml
vault.hashicorp.com/agent-inject-template-db-creds: |
{
{{- with secret "database/creds/db-app" -}}
  "db_connection": "host=postgres port=5432 user={{ .Data.username }} password={{ .Data.password }} dbname=wizard sslmode=disable"
{{- end }}
}
```

Let's step through this line by line.

After the annotation name and pipe, which allows us to define a multi-line string as a value in YAML, we have standard JSON, which denotes the start of an object `{. `.

If you look at the following line, you will see `{{- with secret "database/creds/db-app" -}}`. In the templating language, this reads a secret from `database/creds/db-app` and to then make the data from that operation available to anything inside the block.

Then we have the actual connection string itself; we are creating an attribute on our JSON object called `db_connection,` the contents of this is a standard Go SQL connection for PostgreSQL. The exception to this `{{ .Data.username }}` and `{{ .Data.password }}`. Anything encapsulated by `{{ }}` is a template function or variable. We retrieve the values of the username and password from the secret and write them to the config.

`"db_connection": "host=postgres port=5432 user={{ .Data.username }} password={{ .Data.password }} dbname=wizard sslmode=disable"`

Finally, we close the secret block with `{{- end }}.`

Once this has been processed the output will look something like:

```json
{
  "db_connection": "host=postgres port=5432 user=abcsdsde23sddf password=2323kjc898dfs dbname=wizard sslmode=disable"
}
```

The final part of the annotations is to specify the role which will be used by the sidecar authentication; this is the role you created earlier when configuring Vault.

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
          {{- with secret "database/creds/db-app" -}}
          "db_connection": "postgresql://{{ .Data.username }}:{{ .Data.password }}@postgres:5432/wizard"
          {{- end }}
          }
        vault.hashicorp.com/role: "web"
        vault.hashicorp.com/service: "http://vault"
    spec:
      serviceAccountName: web
      containers:
        - name: web
          image: nicholasjackson/fake-service:v0.7.3
```

This can then be deployed in the usual Kubernetes way.

```bash
kubectl apply -f ./config/web.yml
```

The injector automatically modifies your deployment, adding a `vault-agent` container which has been configured to authenticate with the Vault, and to write the secrets into a shared volume.

You can see this in action by running the following command; you will see the secrets which have been written as a JSON file. Whenever the secrets expire, Vault will automatically regenerate this file; your application can watch for changes reloading the configuration as necessary.

```
kubectl exec -it $(kubectl get pods --selector "app=web" -o jsonpath="{.items[0].metadata.name}")\
 -c web cat /vault/secrets/db-creds
```

Since the deployment contains two pods, you can also run the following command to look at the second pod; you will see that each pod has been allocated unique database credentials.

```
kubectl exec -it $(kubectl get pods --selector "app=web" -o jsonpath="{.items[1].metadata.name}")\
 -c web cat /vault/secrets/db-creds
```

![](https://www.datocms-assets.com/2885/1576781368-7secrets.svg)

## Summary
In this post, we have introduced some of the workflow concepts behind HashiCorp Vault; you have also learned how you can automatically inject secrets into a Kubernetes deployment. While we have focused on dynamic database secrets for PostgreSQL, Vault supports many more different types of secret engine. 

To learn more about Vault, please check out our Learn website [https://learn.hashicorp.com](https://learn.hashicorp.com).

You can also learn more about the various secrets engines in Vault and its API at [https://vaultproject.io](https://vaultproject.io)