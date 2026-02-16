package main

import (
	"fmt"
	"log"
	"net/http"

	"github.com/kendricklawton/project-platform/core/internal/api"
	"github.com/kendricklawton/project-platform/core/internal/config"
	"github.com/kendricklawton/project-platform/core/internal/db"
	"github.com/kendricklawton/project-platform/core/internal/k8s"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("CRITICAL: Failed to load config: %v", err)
	}

	store, err := db.Connect(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("CRITICAL: %v", err)
	}
	defer store.Close()
	log.Println("✅ Connected to PostgreSQL")

	k8sClient, err := k8s.NewClient(cfg.KubeConfigPath)
	if err != nil {
		log.Fatalf("CRITICAL: Failed to connect to K8s: %v", err)
	}
	log.Println("✅ Connected to Kubernetes")

	handler := api.NewHandler(k8sClient, store, cfg.WorkOSAPIKey, cfg.WorkOSClientID)

	log.Printf("🚀 Starting API server on port %d...", cfg.Port)
	if err := http.ListenAndServe(fmt.Sprintf(":%d", cfg.Port), handler.Routes()); err != nil {
		log.Fatalf("Server crashed: %v", err)
	}
}
