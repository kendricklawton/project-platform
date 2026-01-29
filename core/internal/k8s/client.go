package k8s

import (
	"fmt"
	"path/filepath"

	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/util/homedir"
)

// Client holds the standard Kubernetes clientset
type Client struct {
	Clientset *kubernetes.Clientset
}

// NewClient initializes a connection to the cluster.
// It attempts to load in-cluster config first (production),
// then falls back to local kubeconfig (development).
func NewClient(kubeconfigPath string) (*Client, error) {
	var config *rest.Config
	var err error

	// 1. Try In-Cluster Config (Production/Pod)
	config, err = rest.InClusterConfig()
	if err != nil {
		// 2. Fallback to Local Kubeconfig (Development)
		if kubeconfigPath == "" {
			if home := homedir.HomeDir(); home != "" {
				kubeconfigPath = filepath.Join(home, ".kube", "config")
			}
		}

		fmt.Printf("Using local kubeconfig: %s\n", kubeconfigPath)
		config, err = clientcmd.BuildConfigFromFlags("", kubeconfigPath)
		if err != nil {
			return nil, fmt.Errorf("failed to load kubeconfig: %w", err)
		}
	}

	// 3. Create the Clientset
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create k8s client: %w", err)
	}

	return &Client{Clientset: clientset}, nil
}
