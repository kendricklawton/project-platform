package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"text/template"
)

// NOTE: TestGenerateNetplan was removed because Netplan is now handled by Packer.

func TestGenerateK3sConfig_Server(t *testing.T) {
	cfg := &Config{
		Role:         "server",
		Hostname:     "server-01",
		K3sToken:     "test-token",
		PrivateIP:    "10.0.0.2",
		TailscaleIP:  "100.64.0.1",
		LBIP:         "1.1.1.1",
		EtcdS3Access: "access",
		EtcdS3Secret: "secret",
		EtcdS3Bucket: "bucket",
		IsInit:       true,
	}

	content, err := generateK3sConfig(cfg)
	if err != nil {
		t.Fatalf("generateK3sConfig failed: %v", err)
	}

	expectedSubstrings := []string{
		"token: test-token",
		"node-ip: 10.0.0.2",
		"node-external-ip: 100.64.0.1",
		"cloud-provider=external",
		"tls-san:",
		"- server-01",
		"- 100.64.0.1",
		"- 1.1.1.1",
		"etcd-s3: true",
		"etcd-s3-bucket: bucket",
		"cluster-init: true",
	}

	for _, s := range expectedSubstrings {
		if !strings.Contains(content, s) {
			t.Errorf("K3s server config missing expected substring: %q", s)
		}
	}
}

func TestGenerateK3sConfig_Agent(t *testing.T) {
	cfg := &Config{
		Role:        "agent",
		K3sToken:    "test-token",
		PrivateIP:   "10.0.0.3",
		TailscaleIP: "100.64.0.2",
		K3sURL:      "https://1.1.1.1:6443",
	}

	content, err := generateK3sConfig(cfg)
	if err != nil {
		t.Fatalf("generateK3sConfig failed: %v", err)
	}

	expectedSubstrings := []string{
		"token: test-token",
		"node-ip: 10.0.0.3",
		"node-external-ip: 100.64.0.2",
		"server: https://1.1.1.1:6443",
	}

	for _, s := range expectedSubstrings {
		if !strings.Contains(content, s) {
			t.Errorf("K3s agent config missing expected substring: %q", s)
		}
	}

	if strings.Contains(content, "etcd-s3: true") {
		t.Errorf("K3s agent config should not contain etcd-s3 configuration")
	}
}

func TestWriteManifests(t *testing.T) {
	// 1. Setup Temp Dir to mimic /var/lib/rancher/k3s/server/manifests
	tmpDir, err := os.MkdirTemp("", "bootstrap-test")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	// 2. Override the global variable for output path
	manifestDir = tmpDir

	// 3. Create Dummy Config with Versions
	cfg := &Config{
		Role:                "server",
		Hostname:            "server-01",
		CloudEnv:            "dev",
		HcloudToken:         "token",
		HcloudNetwork:       "network",
		LetsEncryptEmail:    "mail@example.com",
		HcloudCCMVersion:    "1.29.1",
		HcloudCSIVersion:    "2.6.0",
		CiliumVersion:       "1.15.1",
		IngressNginxVersion: "4.10.0",
		CertManagerVersion:  "v1.14.0",
		NatsVersion:         "1.2.4",
	}

	// 4. Run the Function
	if err := writeManifests(cfg); err != nil {
		t.Fatalf("writeManifests failed: %v", err)
	}

	// 5. Verify a few files exist and contain the variables
	files, err := os.ReadDir(tmpDir)
	if err != nil {
		t.Fatalf("Failed to read output dir: %v", err)
	}
	if len(files) == 0 {
		t.Error("No manifests were written")
	}

	// Check Cilium Version Injection (if the file exists)
	ciliumPath := filepath.Join(tmpDir, "04-cilium.yaml")
	if _, err := os.Stat(ciliumPath); err == nil {
		ciliumContent, _ := os.ReadFile(ciliumPath)
		if !strings.Contains(string(ciliumContent), "version: \"1.15.1\"") {
			t.Errorf("04-cilium.yaml missing injected version. Got:\n%s", string(ciliumContent))
		}
	}

	// Check Secret Injection (if the file exists)
	secretPath := filepath.Join(tmpDir, "01-hcloud-secret.yaml")
	if _, err := os.Stat(secretPath); err == nil {
		secretContent, _ := os.ReadFile(secretPath)
		if !strings.Contains(string(secretContent), "token: \"token\"") {
			t.Errorf("01-hcloud-secret.yaml missing token. Got:\n%s", string(secretContent))
		}
	}
}

// TestManifestTemplates_SyntaxOnly ensures all embedded templates
// parse correctly without crashing.
func TestManifestTemplates_SyntaxOnly(t *testing.T) {
	entries, err := manifestFS.ReadDir("manifests")
	if err != nil {
		t.Fatalf("failed to read manifest directory: %v", err)
	}

	// Provide dummy values for all fields used in templates
	cfg := &Config{
		Role:                "server",
		HcloudToken:         "dummy",
		HcloudNetwork:       "dummy",
		LetsEncryptEmail:    "dummy",
		HcloudCCMVersion:    "1.0",
		HcloudCSIVersion:    "1.0",
		CiliumVersion:       "1.0",
		IngressNginxVersion: "1.0",
		CertManagerVersion:  "1.0",
		NatsVersion:         "1.0",
	}

	for _, entry := range entries {
		if !strings.HasSuffix(entry.Name(), ".yaml") {
			continue
		}

		manifestPath := "manifests/" + entry.Name()
		content, err := manifestFS.ReadFile(manifestPath)
		if err != nil {
			t.Errorf("failed to read manifest %s: %v", entry.Name(), err)
			continue
		}

		tmpl, err := template.New(entry.Name()).Parse(string(content))
		if err != nil {
			t.Errorf("failed to parse template %s: %v", entry.Name(), err)
			continue
		}

		var buf bytes.Buffer
		if err := tmpl.Execute(&buf, cfg); err != nil {
			t.Errorf("failed to execute template %s: %v", entry.Name(), err)
		}
	}
}
