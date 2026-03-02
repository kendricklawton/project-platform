package api

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/spf13/viper"
)

// Client is a minimal HTTP client for the platform API.
type Client struct {
	baseURL string
	token   string
	http    *http.Client
}

// New creates a Client from the current viper config.
func New() *Client {
	return &Client{
		baseURL: viper.GetString("api_url"),
		token:   viper.GetString("token"),
		http:    &http.Client{Timeout: 30 * time.Second},
	}
}

// HasToken reports whether an auth token is stored.
func (c *Client) HasToken() bool {
	return c.token != ""
}

func (c *Client) do(method, path string, body any) (*http.Response, error) {
	var buf bytes.Buffer
	if body != nil {
		if err := json.NewEncoder(&buf).Encode(body); err != nil {
			return nil, fmt.Errorf("encoding request body: %w", err)
		}
	}
	req, err := http.NewRequest(method, c.baseURL+path, &buf)
	if err != nil {
		return nil, err
	}
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	return c.http.Do(req)
}

func (c *Client) Get(path string) (*http.Response, error) {
	return c.do(http.MethodGet, path, nil)
}

func (c *Client) Post(path string, body any) (*http.Response, error) {
	return c.do(http.MethodPost, path, body)
}

func (c *Client) Delete(path string) (*http.Response, error) {
	return c.do(http.MethodDelete, path, nil)
}
