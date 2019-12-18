# Dynamically generating database credentials with Vault and Kubernetes

Providing database credentials for your applications has always proved operationally challenging. For optimum security the following concepts regarding database credentials should be implemented:

* Each pod should have a unique set of credentials
* Credentials should be disabled when a pod is terminated
* Credentials should be short lived and rotated frequently
* Access should be restricted by application function, a system which only needs to read a specific table should have database access which grants this particular purpose

While they previously mentioned concepts are essential for reducing the blast radius in the event of an attack, they can prove operationally challenging. The reality is that without automation it is impossible to satisfy these constraints. HashiCorp Vault solves this challenge by enabling operators to provide dynamically generated credentials for applications. Vault manages the lifecycle of credentials, rotating and revoking as required.

In this blog post we are going to look at the Vault secret injector for Kubernetes, this allows an operator or developer to inject Vault secrets into a Kubernetes pod using metadata annotations. In the following example we are using the annotations to inject database credentials into the Deployment. All the authentication with Vault, the management of the credentials are automatically handled by the injector. All your application has to do is to read the credentials.

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

https://github.com/hashicorp/vault-k8s/blob/agent/agent-inject/agent/annotations.go#L12-L99

When the injector is enabled and you submit a new deployment to Kubernetes a mutating web hook modifies your deployment to automatically inject a Vault sidecar. This sidecar manages the authentication to Vault and the retrieval of secrets, secrets are then written to a volume mount which your application can read.

```shell
cat /vault/secrets/db-app
```

We are going to  walk through the full process of configuring Vault and Kubernetes to dynamically create PostgreSQL credentials for a deployment, but before we do, Lets quickly recap the three main concepts in Vault.

## How Vault works

There are three main concepts which are required to use Vault, these are:

* Secrets
* Authentication
* Policy

### Secrets

Secrets can be either static like an API key or a credit card number, or they can be dynamic like auto generated cloud or database credentials.

With static secrets you are responsible for creating and managing the lifecycle the secret. For example, I could securely store my Gmail password in Vault, but it is my responsibility to generate the password and to ensure that I periodically update it.

With dynamic secrets you delegate the responsibility to Vault for creating and managing the lifecycle of a secret. For example, with database credentials like PostgreSQL, I give Vault the root credentials for the database, granting it access to create credentials on my behalf. When I want to log into the database I ask Vault for credentials. Vault makes a connection to the database and generates me a set of restricted access credentials. These ar not permenant but leased, Vault manages the lifecycle,  automatically rotating the password, and revoking the access when it is no longer required.

One of the key features of defence in depth is to rotating credentials, in the event of a breech, credentials which have a strict time to live can dramatically reduce the blast radius.

![request secrets](images/vault-policy-workflow-3.png)

### Authentication

To access secrets in Vault you must be authenticated, authentication is in the form of plugable backends. For example for Kubernetes I can authenticate with Vault using a Kubernetes Service Account Token. For human access you could use something like GitHub tokens. In both of these instances Vault does not directly store the credentials, instead it uses a trusted third party to validate the credentials.  For Kubernetes service tokens, when an application attempts to authenticate with Vault, Vault makes a call back to the Kubernetes API to ensure the validity of the token. It returns an internally managed Vault Token which is used for future requests.

![auth setup](images/vault-policy-workflow-1.svg)

### Policy

Tying together secrets and authentication is policy, policy defines which secrets and what administrative operations an authenticated user can perform. For example as a human user I may have policy which allows me to configure secrets for a PostgresSQL databse, but not generate credentials. An application may have the permission to generate credentials but not configure the backend. Vault policy allows you correctly separate responsibility based on role.

![login proccess](images/vault-policy-workflow-2.svg)

### Process

1. Configure Dynamic secrets integration for PostgreSQL
2. Define policy for accessing the to PostgreSQL secrets
3. Configure Authentication Backend
4. Link the policy to identity in the backend
5. Deploy the application to use the secrets

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

If you do not have access to a Kubernetes cluster with Vault and would like to try the features described in this blog you can use `Shipyard` to create a local Docker based Kubernetes cluster with Vault pre-installed.

```
curl https://shipyard.demo.gs/vault
```

All the example configuration mentioned in this post can be downloaded at:

```
http://github.com/nicholasjackson/vault-demo
```

## Configuring dynamic secrets for PostgreSQL

Before we can configure Vault we need a database, lets deploy our PostgreSQL database, for convenience we are going to deploy this to Kubernetes, however; this is not necessary, you could also use a database which is a managed cloud offering or which is running in a virtual machine or physical hardware.

Lets deploy the database using the example from the examples repo, this will create a deployment in your Kubernetes cluster and a service called `postgres` which pointing to the pod created by the deployment.

```yaml
kubectl apply -f config/postgres.yml
```

![](images/4_postgresql.svg)

### Configuring PostgreSQL in Vault

The way that dynamic secrets for databases work in Vault, is that you have a database backend which is configured for a specific database instance and then multiple roles for that database.

A role defines what access level the dynamic credentials created through Vault will have. For example you can create a role which allows an application to read from a specific table, a role which allows an application to write to a specific table, or a role for DB administrators which allows full access to the database.

The first step is to enable the database backend.

```shell
vault secrets enable database
```

Our example is going to walk through the configuration for PostgreSQL, however; each different type of database secret engine requires slightly different configuration parameters but the workflow for configuration, creating roles and generating credentials is exactly the same.  

### Creating database roles

A role defines the parameters for the credentials which will be generated, for example you can define which tables a user has access to. You can also define the lifecycle of the credentials, how long can they be used for. This is done by writing configuration to the path `database/roles/<role name>`. Lets take a look at the parameters in more depth.

The `db_name` parameter refers to the name of the database connection, we are going to configure the connection for the database in the next step. For now we can set the value `wizard`, as this will be the name of the connection when created.

When a user or application requests credentials, Vault will execute the SQL statement defined in the `creation_statements` parameter. In this example we are going to create a role in the database `wizard` which allows select access to all tables. The `creation_statements` are PostgreSQL standard SQL statements. To make the statement dynamic you can use template variables, these variables will be substituted at runtime by Vault. If you look at the create SQL statement below you will see there are three template variables `{{name}}`, `{{password}}` and `{{expiration}}`:

* `{{name}}` is the randomly generated username that Vault will generate
* `{{password}}` is the randomly generated password
* `{{expiration}}` is the data after which the credentials are no longer valid

```sql
CREATE ROLE '{{name}}' WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';
```

To revoke credentials after they expire, Vault also allows you to define `revocation_statements`. In the example below we are disabling the Login once the TTL expires. We could also do additional things like terminating any running processes, again we are using PostgreSQL compliant SQL, any valid statement can be used. As with `creation_statements` you can use template variables.

```sql
ALTER ROLE "{{name}}" NOLOGIN;
```

Finally we have two parameters `default_ttl` and `max_ttl`. `default_ttl` defines the lease length for a secret, this is set to `1h`, this means you need to renew the lease on a secret every hour.

A lease tells Vault that you are still using the credentials and that it should not automatically revoke them. With the Kubernetes integration for Vault this lease will be automatically managed for you. As long as the pod is running the secret will be kept alive, however once the pod is destroyed Vault will automatically revoke the credentials once the lease expires.

The benefit of this approach is that if the credentials leak, they will be automatically removed after a predetermined time, rather than requiring manual intervention.

The final parameter is `max_ttl`, unlike the `default_ttl` which defines the renewal interval,  `max_ttl` defines the maximum duration which credentials can exist. In this instance we are setting a value of `24hrs`, after this period the credentials can not be renewed and Vault will automatically revoke them. The Vault Kubernetes integration will automatically renew the credentials for you as they expire. All you need to do is handle the renewal process in your application, reading the new credentials, and reloading any database connections. To avoid credentials being revoked while in use the sidecar process will attempt to renew credentials before they expire. This way your application can safely close any open database connections before rolling over to the new credentials.

Lets put all of this together and write the role to Vault:

```bash
vault write database/roles/db-app \
    db_name=wizard \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    revocation_statements="ALTER ROLE \"{{name}}\" NOLOGIN;"\
    default_ttl="1h" \
    max_ttl="24h"
```

### Creating database connections

In the previous step we created a role and in that role we referenced the connection `wizard` which had not yet been created. Lets now create that connection. A connection manages the root access for a database. For example, you have a PostgreSQL server which has a database `wizard` on it. The connection in Vault is the configuration to connect to and authenticate with that database. Like a role you need to configure a number of parameters.

The `plugin_name` parameter configures which database plugin we would like to use, for PostgreSQL we are going to tell Vault that we want to use the `postgresql-database-plugin`.

You also need to define which roles can use this connection with the `allowed_roles` parameter, this will be set to the name of the role created in the previous step, `wizard`.

For Vault to connect to the database, you need to define the connection string by setting the `connection_url` parameter, this is in the form of a standard connection string. we are not hard coding the `username` and `password` in the connection string. Instead we are using template variables. You configure the connection string in this way because Vault has a feature for rotating the root credentials for the database. If you hard coded these values then the connection string would fail to work after root credential rotation.

```
postgresql://{{username}}:{{password}}@postgres:5432/wizard?sslmode=disable"
```

The `rotation_statements` parameter, allows you to define a SQL statement which will be executed when rotating the root credentials. We will see how this works in the next step.

```sql
ALTER ROLE {{username}} WITH PASSWORD '{{password}}';
```

Finally we define `username` and `password`, these are the initial credentials which Vault will use when connecting to your PostgreSQL database.

We write this configuration in the same way as we did for the role using the `vault write` command. The path this time is going to be `database/config/<connection name>`:

```shell
vault write database/config/wizard \
    plugin_name=postgresql-database-plugin \
    allowed_roles="*" \
    connection_url="postgresql://{{username}}:{{password}}@postgres:5432/wizard?sslmode=disable" \
    rotation_statements="ALTER ROLE {{username}} WITH PASSWORD '{{password}}';" \
    username="postgres" \
    password="password" \

```

### Rotating the root credentials

When you create a new database you need to create root credentials which can be used to configure additional users. In simple example we did this by using the `POSTGRES_PASSWORD` environment variable on the container. In production you would not create credentials in this way, however; since Vault can generate credentials for both humans and applications it is a good idea to remove all traces of the initial username and password. 

```yaml
env:
  - name: POSTGRES_PASSWORD
    value: password
```

When you configured the connection in the previous step you defined a `rotation_statements` parameter. When you request Vault rotates root credentials it connects to the database using its existing root credentials. It then generates a new 

```
vault write /database/rotate-root/wizard
```

```shell
kubectl exec -it $(kubectl get pods --selector "app=postgres" -o jsonpath="{.items[0].metadata.name}") -c postgres -- bash -c 'PGPASSWORD=password psql -U postgres'
psql: FATAL:  password authentication failed for user "postgres"
command terminated with exit code 2
```

You can manually check that this is working by manually requesting Vault creates credentials for you, you will see some output similar to that below. Note that both the username and the password are randomly generated and that the initial lease duration corresponds to the `default_ttl`.

```bash
vault read database/creds/db-app
```

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