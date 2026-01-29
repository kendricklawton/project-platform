package main

import (
	"fmt"
	"log"
	"net/http"

	"github.com/kendricklawton/project-platform/core/internal/api"
	"github.com/kendricklawton/project-platform/core/internal/config"
	"github.com/kendricklawton/project-platform/core/internal/k8s"
)

func main() {
	// 1. Load Config
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("CRITICAL: %v", err)
	}

	// 1. Connect to Kubernetes
	k8sClient, err := k8s.NewClient(cfg.KubeConfigPath)
	if err != nil {
		log.Fatalf("Failed to connect to K8s: %v", err)
	}

	// 2. Inject K8s client into the Handler
	handler := api.NewHandler(k8sClient)

	// 3. Start Server
	http.ListenAndServe(fmt.Sprintf(":%d", cfg.Port), handler.Routes())
}
