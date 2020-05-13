package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/hashicorp/go-hclog"
	"github.com/nicholasjackson/demo-vault/transform-engine-go/data"
	"github.com/nicholasjackson/demo-vault/transform-engine-go/vault"
)

// Health is a http.Handler for API status
type Health struct {
	pc  *data.PostgreSQL
	vc  *vault.Client
	log hclog.Logger
}

// NewHealth creates a new health handler
func NewHealth(pc *data.PostgreSQL, vc *vault.Client, log hclog.Logger) *Health {
	return &Health{pc, vc, log}
}

// HealthResponse is returned by the handler
type HealthResponse struct {
	Vault string `json:"vault"`
	DB    string `json:"db"`
}

func (h *Health) ServeHTTP(rw http.ResponseWriter, r *http.Request) {
	hr := &HealthResponse{
		Vault: "OK",
		DB:    "OK",
	}

	status := http.StatusOK

	// check health of Vault
	if ok, _ := h.pc.IsConnected(); !ok {
		hr.DB = "Fail"
		status = http.StatusInternalServerError
	}

	if !h.vc.IsOK() {
		hr.Vault = "Fail"
		status = http.StatusInternalServerError
	}

	rw.WriteHeader(status)
	json.NewEncoder(rw).Encode(hr)

}
