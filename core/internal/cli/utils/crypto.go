package utils

import (
	"crypto/rand"
	"encoding/hex"
)

// GenerateState creates a cryptographically secure random string.
// Since this is in the 'cmds' package, all files in this folder can use it.
func GenerateState(n int) (string, error) {
	bytes := make([]byte, n)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}
