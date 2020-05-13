package main

import (
	"fmt"
	"net/http"
	"time"

	"github.com/gorilla/mux"
	"github.com/hashicorp/go-hclog"
	"github.com/nicholasjackson/demo-vault/transform-engine-go/data"
	"github.com/nicholasjackson/demo-vault/transform-engine-go/handlers"
	"github.com/nicholasjackson/demo-vault/transform-engine-go/vault"
	"github.com/nicholasjackson/env"
)

var postgresHost = env.String("POSTGRES_HOST", false, "localhost", "PostgreSQL server location")
var postgresPort = env.Int("POSTGRES_PORT", false, 5432, "PostgreSQL port")
var vaultHost = env.String("VAULT_ADDR", false, "http://localhost:8200", "Vault server location")

func main() {
	env.Parse()

	var err error
	log := hclog.Default()

	// Create the postgres DB client
	var pc *data.PostgreSQL
	for {
		pc, err = data.NewPostgreSQLClient(fmt.Sprintf("host=%s port=%d user=root password=password dbname=payments sslmode=disable", *postgresHost, *postgresPort))
		if err == nil {
			break
		}

		log.Error("Unable to connect to database", "error", err)
		time.Sleep(5 * time.Second)
	}

	// Create the Vault client
	vc := vault.NewClient("root", *vaultHost)

	// create the HTTP handler
	ph := handlers.NewPayment(pc, vc, log)
	hh := handlers.NewHealth(pc, vc, log)

	r := mux.NewRouter()
	r.Handle("/", ph).Methods(http.MethodPost)
	r.Handle("/health", hh).Methods(http.MethodGet)

	log.Info("Starting server", "bind", ":9090")

	http.ListenAndServe(":9090", r)
}
