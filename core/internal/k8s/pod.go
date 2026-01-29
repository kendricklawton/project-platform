package k8s

import (
	"context"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// GetNodeCount returns the number of nodes in the cluster
func (c *Client) GetNodeCount(ctx context.Context) (int, error) {
	nodes, err := c.Clientset.CoreV1().Nodes().List(ctx, metav1.ListOptions{})
	if err != nil {
		return 0, err
	}
	return len(nodes.Items), nil
}
