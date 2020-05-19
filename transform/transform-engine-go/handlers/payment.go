package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/hashicorp/go-hclog"
	"github.com/nicholasjackson/demo-vault/transform-engine-go/data"
	"github.com/nicholasjackson/demo-vault/transform-engine-go/vault"
)

// Payment is a http.Handler for payment routes
type Payment struct {
	pc  *data.PostgreSQL
	vc  *vault.Client
	log hclog.Logger
}

// NewPayment creates a new payment handler
func NewPayment(pc *data.PostgreSQL, vc *vault.Client, log hclog.Logger) *Payment {
	return &Payment{pc, vc, log}
}

// PaymentRequest is sent as part of the HTTP request
type PaymentRequest struct {
	CardNumber string `json:"card_number"`
	Expiration string `json:"expiration"`
	CV2        string `json:"cv2"`
}

// PaymentResponse is sent with a successful payment
type PaymentResponse struct {
	TransactionID int64 `json:"transaction_id"`
}

// PaymentError is returned when an error occurs
type PaymentError struct {
	Message string `json:"message"`
}

// ServeHTTP implement http.Handler interface
func (p *Payment) ServeHTTP(rw http.ResponseWriter, r *http.Request) {
	// parse the request
	pr := &PaymentRequest{}
	err := json.NewDecoder(r.Body).Decode(pr)
	if err != nil {
		p.log.Error("Unable to parse request", "error", err)

		presp := &PaymentError{fmt.Sprintf("Unable to parse request: %s", err)}
		rw.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(rw).Encode(presp)
		return
	}

	// tokenize the card number
	encoded, err := p.vc.TokenizeCCNumber(pr.CardNumber)
	if err != nil {
		p.log.Error("Unable to tokenize record", "error", err)

		presp := &PaymentError{fmt.Sprintf("Uable to tokenize record: %s", err)}
		rw.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(rw).Encode(presp)
		return
	}

	// save the data into the database
	o := data.Order{CardNumber: encoded}
	id, err := p.pc.SaveOrder(o)
	if err != nil {
		p.log.Error("Unable to save record", "error", err)

		presp := &PaymentError{fmt.Sprintf("Uable to save data to db: %s", err)}
		rw.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(rw).Encode(presp)
		return
	}

	presp := PaymentResponse{id}
	json.NewEncoder(rw).Encode(presp)
}

// Example VISA number
//o := data.Order{CardNumber: "4024-2322-1235-9245"}
// Example MasterCard number
//o = data.Order{CardNumber: "5355-6853-9451-3461"}
