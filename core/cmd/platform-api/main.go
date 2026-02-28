package main

import (
	"context"
	"log"

	"github.com/kendricklawton/project-platform/core/internal/config"
	"github.com/kendricklawton/project-platform/core/internal/db"
	"github.com/kendricklawton/project-platform/core/internal/server"
)

func main() {
	ctx := context.Background()

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config error: %v", err)
	}

	store, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("db connection failed: %v", err)
	}
	defer store.Close()

	srv := server.New(cfg, store, nil)

	log.Printf("🚀 Platform Control Plane running on :%d", cfg.Port)
	if err := srv.Run(); err != nil {
		log.Fatalf("server crashed: %v", err)
	}
}
