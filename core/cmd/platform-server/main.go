package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/kendricklawton/project-platform/core/internal/config"
	"github.com/kendricklawton/project-platform/core/internal/db"
	"github.com/kendricklawton/project-platform/core/internal/server"
)

func main() {
	ctx := context.Background()

	cfg, err := config.LoadServer()
	if err != nil {
		log.Fatalf("API config error: %v", err)
	}

	store, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("db connection failed: %v", err)
	}
	defer store.Close()

	srv := server.New(cfg, store, nil)

	// 1. Run the server in a separate goroutine so it doesn't block main
	go func() {
		log.Printf("🚀 Platform Control Plane running on :%d", cfg.Port)
		// We ignore http.ErrServerClosed because that is the expected error when we call Shutdown()
		if err := srv.Run(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("server crashed: %v", err)
		}
	}()

	// 2. Create a channel to listen for OS interrupt signals (Ctrl+C)
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, os.Interrupt, syscall.SIGTERM)

	// 3. Block here until a signal is received
	<-quit
	log.Println("🛑 Shutting down server gracefully...")

	// 4. Create a timeout context so it doesn't hang forever if a connection is stuck
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("✅ Server exited cleanly")
}
