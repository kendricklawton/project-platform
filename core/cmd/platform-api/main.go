package main

import (
	"log"

	"github.com/kendricklawton/project-platform/core/internal/config"
	"github.com/kendricklawton/project-platform/core/internal/db"
	"github.com/kendricklawton/project-platform/core/internal/server"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config error: %v", err)
	}

	store, err := db.Connect(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("db connection failed: %v", err)
	}
	defer store.Close()

	// The wiring logic is now safely isolated in the internal/server package
	srv := server.New(cfg, store, nil)

	log.Printf("🚀 Platform Control Plane running on :%d", cfg.Port)
	if err := srv.Run(); err != nil {
		log.Fatalf("server crashed: %v", err)
	}
}
