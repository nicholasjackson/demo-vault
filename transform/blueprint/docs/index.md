---
id: index
title: Vault Transform - Go Microservice example
sidebar_label: Introduction
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

Vault 1.4 called Transform. Transform is a Secrets Engine that allows Vault to encode and decode sensitive values residing in external systems such as databases or file systems. This capability allows Vault to ensure that when an encoded secret’s residence system is compromised, such as when a database is breached and its data is exfiltrated, that those encoded secrets remain uncompromised even when held by an adversary.

This post will show you how to implement Transform secrets using Go and PostgreSQL. For information on the technical detail behind the Transform engine
please see Andy's excelent article [https://www.hashicorp.com/blog/transform-secrets-engine](https://www.hashicorp.com/blog/transform-secrets-engine).

## API Structure
Our example application is a simple RESTful payment service, there is a single route which accepts a POST request.

```
POST /order
Content-Type: application/json
```

### Request
The data for the API is a simple JSON data structure which contains a single field for the card number.

```json
{
  "card_number": "1234-1234-1234-1234",
  "card_expiration": "10/12",
  "cv2": "123"
}
```

### Response

On a succesfull call to the API, the data is saved to the database and a transaction ID is returned to the caller.

```json
{
  "transaction_id": "1234"
}
```

## Requirements
The payment service does not immedidately process the payments for the orders, instead it stores the card numbers in a PostgreSQL database until application  picks them up for processing. The applcation has the following requirements:

* Credit card details must be stored in the database in an encrypted format
* It must be possible to query details of the card number without decrypting it

The first requirement is fairly trivial to solve using Vault using the [Transit Secrets Engine](https://www.vaultproject.io/docs/secrets/transit/). Transit secrets can be used as encryption as service to encrypt the credit card details before they are written to the database. The problem is second requirement, for example you wish to know the number of AMEX cards awating processing.

A credit card number is composed from three different parts, the `Issuer Number`, the `Account Number` and the `Checksum`.

![](./images/card.png)

`Issuer Number` relates to the type of the card (first digit), and the issuers code this is the information which you would like to query to satisfy the second requirement.

To enable this you either have to manually partially encrypt the card number or you have to store metadata for the card. This of course is possible however control of the process can not be centrally managed. It requires developers working with the data to understand and implement the process. 

One of the benefits of the `Transit Secrets Engine` for developers is that they do not need to worry about if they have correctly implemented the encryption correctly. Operators do not need to worry if they have provided the applicaion the means to encrypt data. Info security do not need to worry that central policy regarding the handling of PII has been adhered.

Using the `Transit Secrets Engine` a developer only needed to call a simple API and store the result.

With this new requirement for searching information the developer now has the responsiblity for managing the complexity of partially encrypting the credit card data, Info security need to worry about the correct implementation of this.

## Transform Secrets Engine
The solution is to use the Transform Secrets Engine, Transform Secrets allows the definition of the encription structure as a central concern. Developers can call a simple API which allows them to encrypt the data as required.

To satisfy your second requirement a transform could be defined which would take a card number for example `1234-5624-6310-0053` and encrypt the sensitive parts, while retaining the formatting and the ability to infer information about the card type and issuing bank. 

The transform engine allows you to define a pattern using regular expressions, the capture groups inside of the regular expressions are replaced
with cyphertext. Anything outside the match groups are left in the original format. To encrypt only the account number and checksum for your cards you could use the following regular expression.

```
\d{4}-\d{2}(\d{2})-(\d{4})-(\d{4})
```

Given an input of:

```
1234-5611-1111-1111
```

You would get a cyphertext output of:

```
1234-5672-6649-0472
```

Note that the first 6 digits have not been encrypted. 

## Configuring Transform Secrets

To use Transform secrets you must be using Vault Enterprise version 1.4 or above. You can enable the Transform secrets engine with the following command.

```
vault secrets enable transform
```

<Terminal target="vault.container.shipyard.run" shell="/bin/sh" workdir="/" user="root" expanded />
<p></p>

The Transform secrets engine contains several types of resources that encapsulate different aspects of the information required in order to perform data transformation.

* Roles are the basic high-level construct that holds the set of transformation that it is allowed to performed. The role name is provided when performing encode and decode operations.

* Transformations hold information about a particular transformation. It contains information about the type of transformation that we want to perform, the template that it should use for value detection, and other transformation-specific values such as the tweak source or the masking character to use.

* Templates allow us to determine what and how to capture the value that we want to transform.

* Alphabets provide the set of valid UTF-8 character contained within both the input and transformed value on FPE transformations.

Let's see how each of these elements is confiugred:

First we need to create a role, when creating the role you need to provide the list of transformations which can be used from this role. 

```
vault write transform/role/payments transformations=ccn-fpe
```

<Terminal target="vault.container.shipyard.run" shell="/bin/sh" workdir="/" user="root" expanded />
<p></p>

Then we can create a Transform:

```
vault write transform/transformation/ccn-fpe \
type=fpe \
template=ccn \
tweak_source=internal \
allowed_roles=payments
```

<Terminal target="vault.container.shipyard.run" shell="/bin/sh" workdir="/" user="root" />

Then define the template

```
vault write transform/template/ccn \
type=regex \
pattern='\d{4}-\d{2}(\d{2})-(\d{4})-(\d{4})' \
alphabet=numerics
```

<Terminal target="vault.container.shipyard.run" shell="/bin/sh" workdir="/" user="root" />

Optionally we can create a custom alphabet, the custom alphabet allows us to define the characters which will be used in the output of the cyphertext.

```shell
vault write transform/alphabet/numerics \
alphabet="0123456789"
```

<Terminal target="vault.container.shipyard.run" shell="/bin/sh" workdir="/" user="root" />

## Testing the setup

Now all of that is configured you can test the setup

```
vault write transform/encode/payments value=1111-2222-3333-4444
```

<Terminal target="vault.container.shipyard.run" shell="/bin/sh" workdir="/" user="root" />

You should see some output which looks similar to the following

```
Key              Value
---              -----
encoded_value    1111-2200-1452-4879
```

Note that the first 6 digits of the returne cyphertext are the same as the original data.

You can reverse the operation with the following command.

```
vault write transform/decode/payments value=<encoded_vaule>

vault write transform/decode/payments value=1111-2200-1452-4879
```
<p>
  <Terminal target="vault.container.shipyard.run" shell="/bin/sh" workdir="/" user="root" />
</p>


## Using Transform from your application

So far you have seen how you can use the Transform engine using the CLI, Vault has a comprehensive API, everything possible using the CLI is also possible using the RESTful API. To interact with the Vault API you have three options:

1. Use one of the [Client libraries](https://www.vaultproject.io/api/libraries.html)
1. Code generate your own client using the [OpenAPI v3 specifications](https://www.vaultproject.io/api-docs/system/internal-specs-openapi)
1. Manually interact with the HTTP API 

The third example is the one we are going to use as it demonstrates the simplicity rather nicely for interaction with Vault.

Since the example application only needs to encode data and not manage the configuration for Transform it only needs to interact with a single API endpoint which is Encode.

https://www.vaultproject.io/api-docs/secret/transform#encode

To encode data using Transform you `POST` a JSON payload to the path `/v1/transform/encode/:role_name`, where in this example `:role_name` would be `payments` which is the name of the role created earlier. 

The API requires that you have a valid Vault token and that token has the correct policy allocated to it in order to perform the operation. The Vault token is sent to the request using the `X-Vault-Token` HTTP header. 

The payload for the request is a simple JSON structure with a single field `value`, you can see an example below

```json
{
  "value": "1111-2222-3333-4444"
}
```

If we were to use `cURL` to submit this request the code would look like this:

```shell
curl localhost:8200/v1/transform/encode/payments \
  -H 'X-Vault-Token: root' \
  -d '{"value": "1111-2222-3333-4444"}'
```

Vault will return the cyphertext as part of a JSON response, this value is returned at the path `.data.encoded_value` as can be seen in the example output below.

```json
{
  "request_id": "0f170922-d7c1-0137-391b-932a2025beb4",
  "lease_id": "",
  "renewable": false,
  "lease_duration": 0,
  "data": {
    "encoded_value": "1111-2208-4340-0589"
  },
  "wrap_info": null,
  "warnings": null,
  "auth": null
}
```

## Interacting with the Vault API from Java and Go

The first thing we need to do is to construct a byte array which holding a JSON formatted string for our payload.

<Tabs
  defaultValue="go"
  values={[
    { label: 'Go', value: 'go', },
    { label: 'Java', value: 'java', }
  ]
}>

<TabItem value="go">

```go
// create the JSON request as a byte array
req := TokenRequest{Value: cc}
data, _ := json.Marshal(req)
```

</TabItem>

<TabItem value="java">

```java
// create the request
TokenRequest req = new TokenRequest(cardNumber);

// convert the POJO to a byte array 
ObjectMapper mapper = new ObjectMapper();
mapper.enable(SerializationFeature.INDENT_OUTPUT);
byte[] byteRequest = mapper.writeValueAsBytes(req);
```

</TabItem>

</Tabs>

Then you can construct the request, ensuring the payload is written as part of the request body.

<Tabs
  defaultValue="go"
  values={[
    { label: 'Go', value: 'go', },
    { label: 'Java', value: 'java', }
  ]
}>

<TabItem value="go">

```go
url := fmt.Sprintf("http://%s/v1/transform/encode/payments", c.uri)
r, _ := http.NewRequest(http.MethodPost, url, bytes.NewReader(data))
r.Header.Add("X-Vault-Token", "root")

resp, err := http.DefaultClient.Do(r)
if err != nil {
	return "", err
}
defer resp.Body.Close()

if resp.StatusCode != http.StatusOK {
	return "", fmt.Errorf("Vault returned reponse code %d, expected status code 200", resp.StatusCode)
}
```

</TabItem>

<TabItem value="java">

```java
// make a call to vault to process the request
URL url = new URL(this.url);
HttpURLConnection con = (HttpURLConnection)url.openConnection();
con.setDoOutput(true);    
con.setRequestMethod("POST");
con.setRequestProperty("Content-Type", "application/json; utf-8");
con.setRequestProperty("Accept", "application/json");
con.setRequestProperty("X-Vault-Token", this.token);

// write the body
try(OutputStream os = con.getOutputStream()) {
  os.write(byteRequest, 0, byteRequest.length);           
}
```

</TabItem>

</Tabs>

Finally the response can be read from the HTTP response body and parsed back into a native object.

<Tabs
  defaultValue="go"
  values={[
    { label: 'Go', value: 'go', },
    { label: 'Java', value: 'java', }
  ]
}>

<TabItem value="go">

```go
// process the response
tr := &TokenResponse{}
err = json.NewDecoder(resp.Body).Decode(tr)
if err != nil {
	return "", err
}
```

</TabItem>

<TabItem value="java">

```java
// read the response
TokenResponse resp = new ObjectMapper()
  .readerFor(TokenResponse.class)
  .readValue(con.getInputStream());
```

</TabItem>

</Tabs>

## Testing the service

Let's test the service, the demo has both the Java and the Go code running

<Tabs
  defaultValue="go"
  values={[
    { label: 'Go', value: 'go', },
    { label: 'Java', value: 'java', }
  ]
}>

<TabItem value="go">

```shell
curl payments-go.container.shipyard.run:9090 -H "content-type: application/json" -d '{"card_number": "1234-1234-1234-1234"}'
```

</TabItem>

<TabItem value="java">

```shell
curl payments-java.container.shipyard.run:9090 -H "content-type: application/json" -d '{"card_number": "1234-1234-1234-1234"}'
```

</TabItem>
</Tabs>

<Terminal target="payments-go.container.shipyard.run" shell="sh" workdir="/" user="root"/>

You should see a response something like the following

```json
{"transaction_id": 11}
```

If you query the orders table on the database you will be able to see the encrypted value for this transaction

```
PGPASSWORD=password psql -h localhost -p 5432 -U root -d payments -c 'SELECT * from orders;'
```

<Terminal target="postgres.container.shipyard.run" shell="/bin/bash" workdir="/" user="root"/>

Using the command from earlier you can 

```shell
vault write transform/decode/payments value=<card_number>
```

<Terminal target="vault.container.shipyard.run" shell="sh" workdir="/" user="root"/>

## Summary

In this demo you have seen how you can 