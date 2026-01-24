package api

// LoginResponse returns the WorkOS AuthKit URL.
type LoginResponse struct {
	Url string `json:"url"`
}

// ExchangeRequest is the body for POST /auth/exchange.
type ExchangeRequest struct {
	HandoffCode string `json:"handoff_code" binding:"required"`
}

// ExchangeResponse returns the session data.
type ExchangeResponse struct {
	AccessToken  string  `json:"access_token"`
	Email        string  `json:"email"`
	ExpiresIn    *int    `json:"expires_in,omitempty"`
	RefreshToken *string `json:"refresh_token,omitempty"`
	SessionId    *string `json:"session_id,omitempty"`
}

// ErrorResponse is the standard error format.
type ErrorResponse struct {
	Details          *string `json:"details,omitempty"`
	Error            string  `json:"error"`
	ErrorDescription *string `json:"error_description,omitempty"`
}
