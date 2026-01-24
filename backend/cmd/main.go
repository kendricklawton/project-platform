package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"

	"github.com/kendricklawton/project-dupes/backend/internal/config"
	"github.com/kendricklawton/project-dupes/backend/internal/handler"
	"github.com/kendricklawton/project-dupes/backend/internal/middleware"
	"github.com/kendricklawton/project-dupes/backend/internal/store"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	_ = godotenv.Load()

	appConfig, err := config.LoadConfig()
	if err != nil {
		logger.Error("config_init_failed", slog.Any("error", err))
		os.Exit(1)
	}

	var memoryStore store.MemoryStore
	if appConfig.Environment == "production" {
		s, err := store.NewRedisStore(appConfig.RedisURL)
		if err != nil {
			logger.Error("redis_init_failed", slog.Any("error", err))
			os.Exit(1)
		}
		memoryStore = s
		logger.Info("using_redis_handoff_store")
	} else {
		memoryStore = store.NewLocalStore()
		logger.Info("using_in_memory_handoff_store")
	}

	// 4. Initialize Handler
	authHandler := handler.NewAuthHandler(appConfig, logger, memoryStore)

	// 5. Setup Router
	router := gin.New()
	router.Use(gin.Recovery())
	router.Use(middleware.SlogMiddleware(logger))

	authGroup := router.Group("/auth")
	{
		authGroup.GET("/login", authHandler.Login)
		authGroup.GET("/callback", authHandler.Callback)
		authGroup.POST("/exchange", authHandler.Exchange)
		// authGroup.GET("/logout", authHandler.Logout)
	}

	router.GET("/healthz", func(c *gin.Context) { c.Status(http.StatusOK) })

	srv := &http.Server{
		Addr:    ":" + appConfig.Port,
		Handler: router,
	}

	go func() {
		logger.Info("server_starting", slog.String("port", appConfig.Port))
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Error("server_failed_to_start", slog.Any("error", err))
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Info("shutting_down_server")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		logger.Error("server_forced_to_shutdown", slog.Any("error", err))
	}

	logger.Info("server_exited")
}
