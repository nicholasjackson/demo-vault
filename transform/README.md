# Format preserving Encryption with the Vault Transform Secrets Engine
This demo shows how to use the Transform secrets engine to encrypt data while preserving data formatting.

Note: This demo uses Vault Enterprise 1.4, Vault Enterprise in trial mode is limited to sessions of 30 minutes before the Vault server will enter sealed state. You will need to restart the server to reactivate the trial.

## Requirements:
* Docker []()
* Shipyard [https://shipyard.run/docs/install](https://shipyard.run/docs/install)

```json
{
  "card_number": "1234-1234-1234-1234",
  "expiration": "0423",
  "cv2": "123"
}

```

## Running the demo
The demo uses Shipyard to start a Vault server and example application in Docker on your local machine. To run the demo use the following command:

```shell
➜ shipyard run ./blueprint 
Running configuration from:  ./blueprint

2020-06-02T07:10:00.190+0100 [DEBUG] Statefile does not exist
2020-06-02T07:10:00.191+0100 [INFO]  Creating Network: ref=local
```

Once started interactive documentation can be run for the demo at [http://docs.docs.shipyard.run:8080/docs/index](http://docs.docs.shipyard.run:8080/docs/index). The Vault server, Postgres server and example applications are also accessible from your terminal at the following locations:

* Vault `localhost:8200`
* PostgreSQL `localhost:5432` DB: `payments`, User: `root`, Pass: `password`
* Java example application `localhost:9092`
* Go example application  `localhost:9091`

## Stopping the demo
To stop the demo and clean up resources, run the following command:

```shell
demo-vault/transform on  master [!] via 🐹 v1.13.8 on 🐳 v19.03.10 () 
➜ shipyard destroy
2020-06-02T07:08:14.044+0100 [INFO]  Destroy Container: ref=vault
2020-06-02T07:08:14.045+0100 [INFO]  Destroy Container: ref=payments_go
2020-06-02T07:08:14.045+0100 [INFO]  Destroy Container: ref=payments_java
2020-06-02T07:08:14.045+0100 [INFO]  Destroy Container: ref=postgres
2020-06-02T07:08:14.045+0100 [INFO]  Destroy Documentation: ref=docs
2020-06-02T07:08:15.506+0100 [INFO]  Destroy Network: ref=local
```

## Source Code
Source code for the example applications can be found in this repository at the following locations:
* Go [./transform-engine-go](./transform-engine-go)
* Java [./transform-engine-java](./transform-engine-java)