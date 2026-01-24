// backend/internal/middleware/middleware.go
package middleware

import (
	"log/slog"
	"time"

	"github.com/gin-gonic/gin"
)

func SlogMiddleware(logger *slog.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		method := c.Request.Method

		c.Next()

		latency := time.Since(start)
		status := c.Writer.Status()

		// Structured logging makes debugging easy.
		// We use Warn for 4xx and Error for 5xx.
		logFn := logger.Info
		if status >= 500 {
			logFn = logger.Error
		} else if status >= 400 {
			logFn = logger.Warn
		}

		logFn("http_request",
			"status", status,
			"method", method,
			"path", path,
			"latency", latency,
			"ip", c.ClientIP(),
		)
	}
}
