package vault

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
)

type Client struct {
	token string
	uri   string
}

type TokenRequest struct {
	Value string `json:"value"`
}

type TokenResponse struct {
	Data TokenReponseData `json:"data"`
}

type TokenReponseData struct {
	EncodedValue string `json:"encoded_value"`
}

// NewClient creates a new Vault client
func NewClient(token, serverURI string) *Client {
	return &Client{token, serverURI}
}

// IsOK returns true if Vault is unsealed and can accept requests
func (c *Client) IsOK() bool {
	url := fmt.Sprintf("%s/v1/sys/health", c.uri)

	r, _ := http.NewRequest(http.MethodGet, url, nil)
	r.Header.Add("X-Vault-Token", c.token)

	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		return false
	}

	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return false
	}

	return true
}

// TokenizeCCNumber uses the Vault API to tokenize the given string
func (c *Client) TokenizeCCNumber(cc string) (string, error) {
	// create the JSON request as a byte array
	req := TokenRequest{Value: cc}
	data, _ := json.Marshal(req)

	// call the api
	url := fmt.Sprintf("%s/v1/transform/encode/payments", c.uri)
	r, _ := http.NewRequest(http.MethodPost, url, bytes.NewReader(data))
	r.Header.Add("X-Vault-Token", c.token)

	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("Vault returned reponse code %d, expected status code 200", resp.StatusCode)
	}

	// process the response
	tr := &TokenResponse{}
	err = json.NewDecoder(resp.Body).Decode(tr)
	if err != nil {
		return "", err
	}

	return tr.Data.EncodedValue, nil
}
