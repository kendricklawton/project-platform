package main

import (
	"bytes"
	"crypto/tls"
	"embed"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"text/template"
	"time"
)

//go:embed manifests/*.yaml
var manifestFS embed.FS

// GLOBAL VERSIONS (Injected via -ldflags)
var (
	HcloudCCMVersion    = "1.29.1"
	HcloudCSIVersion    = "2.6.0"
	CiliumVersion       = "1.15.1"
	IngressNginxVersion = "4.10.0"
	CertManagerVersion  = "v1.14.0"
	NatsVersion         = "1.2.4"
)

// CONFIGURATION PATHS
var (
	k3sConfigPath = "/etc/rancher/k3s/config.yaml"
	manifestDir   = "/var/lib/rancher/k3s/server/manifests"
)

const (
	maxRetries    = 60
	retryInterval = 5 * time.Second
)

type Config struct {
	Role             string
	Hostname         string
	CloudEnv         string
	K3sToken         string
	LBIP             string
	K3sURL           string // For agents
	TailscaleKey     string
	TailscaleTag     string
	PrivateIP        string
	TailscaleIP      string
	Interface        string
	IsInit           bool   // Is this the first master node?
	EtcdS3Bucket     string // Server only
	EtcdS3Access     string // Server only
	EtcdS3Secret     string // Server only
	HcloudToken      string // Server only
	HcloudNetwork    string // Server only
	LetsEncryptEmail string // Server only

	// Component Versions
	HcloudCCMVersion    string
	HcloudCSIVersion    string
	CiliumVersion       string
	IngressNginxVersion string
	CertManagerVersion  string
	NatsVersion         string
}

func main() {
	// FAIL FAST: Ensure versions were injected
	if err := validateVersions(); err != nil {
		log.Fatalf("CRITICAL CONFIG ERROR: %v", err)
	}

	cfg := parseFlags()

	log.Println("=== Starting Node Bootstrap (Go) ===")
	log.Printf("Role: %s, Hostname: %s, Environment: %s", cfg.Role, cfg.Hostname, cfg.CloudEnv)

	// We no longer configure Netplan/Routes here; Packer's baked image handles that.
	if err := detectNetwork(cfg); err != nil {
		log.Fatalf("Network detection failed: %v", err)
	}

	if err := setupTailscale(cfg); err != nil {
		log.Fatalf("Tailscale setup failed: %v", err)
	}

	if err := configureK3s(cfg); err != nil {
		log.Fatalf("K3s configuration failed: %v", err)
	}

	if cfg.Role == "server" {
		if err := writeManifests(cfg); err != nil {
			log.Fatalf("Failed to write manifests: %v", err)
		}
	}

	if err := startK3s(cfg); err != nil {
		log.Fatalf("Failed to start K3s: %v", err)
	}

	if !cfg.IsInit && (cfg.Role == "agent" || cfg.Role == "server") {
		target := cfg.LBIP
		if cfg.Role == "agent" {
			target = cfg.K3sURL
		}
		if err := waitForAPI(target); err != nil {
			log.Printf("WARNING: API check failed: %v. Proceeding anyway...", err)
		}
	}

	if cfg.Role == "server" {
		if err := finalizeTaints(cfg); err != nil {
			log.Printf("WARNING: Failed to remove taints: %v", err)
		}
	}

	log.Println("=== Bootstrap Complete ===")
}

// validateVersions ensures that the binary was built with -ldflags
func validateVersions() error {
	missing := []string{}
	if HcloudCCMVersion == "" {
		missing = append(missing, "HcloudCCMVersion")
	}
	if HcloudCSIVersion == "" {
		missing = append(missing, "HcloudCSIVersion")
	}
	if CiliumVersion == "" {
		missing = append(missing, "CiliumVersion")
	}
	if IngressNginxVersion == "" {
		missing = append(missing, "IngressNginxVersion")
	}
	if CertManagerVersion == "" {
		missing = append(missing, "CertManagerVersion")
	}
	if NatsVersion == "" {
		missing = append(missing, "NatsVersion")
	}

	if len(missing) > 0 {
		return fmt.Errorf("build versions are missing! Missing: %s", strings.Join(missing, ", "))
	}
	return nil
}

func parseFlags() *Config {
	cfg := &Config{}
	flag.StringVar(&cfg.Role, "role", "agent", "Role: server or agent")
	flag.StringVar(&cfg.Hostname, "hostname", "", "Node hostname")
	flag.StringVar(&cfg.CloudEnv, "cloud-env", "dev", "Cloud environment (dev/prod)")
	flag.StringVar(&cfg.K3sToken, "k3s-token", "", "K3s cluster token")
	flag.StringVar(&cfg.LBIP, "load-balancer-ip", "", "Load Balancer IP")
	flag.StringVar(&cfg.K3sURL, "k3s-url", "", "K3s URL (for agents)")
	flag.StringVar(&cfg.TailscaleKey, "tailscale-auth-key", "", "Tailscale Auth Key")
	flag.StringVar(&cfg.TailscaleTag, "tailscale-tag", "", "Tailscale Tag Override")
	flag.BoolVar(&cfg.IsInit, "init", false, "Is this the cluster init node?")

	// Server specific
	flag.StringVar(&cfg.EtcdS3Bucket, "s3-bucket", "", "S3 Bucket")
	flag.StringVar(&cfg.EtcdS3Access, "s3-access", "", "S3 Access Key")
	flag.StringVar(&cfg.EtcdS3Secret, "s3-secret", "", "S3 Secret Key")
	flag.StringVar(&cfg.HcloudToken, "hcloud-token", "", "Hetzner API Token")
	flag.StringVar(&cfg.HcloudNetwork, "hcloud-network-name", "", "Hetzner Network Name")
	flag.StringVar(&cfg.LetsEncryptEmail, "letsencrypt-email", "", "Let's Encrypt Email")

	// Component Versions
	flag.StringVar(&cfg.HcloudCCMVersion, "hcloud-ccm-version", HcloudCCMVersion, "Hetzner CCM Version")
	flag.StringVar(&cfg.HcloudCSIVersion, "hcloud-csi-version", HcloudCSIVersion, "Hetzner CSI Version")
	flag.StringVar(&cfg.CiliumVersion, "cilium-version", CiliumVersion, "Cilium Version")
	flag.StringVar(&cfg.IngressNginxVersion, "ingress-nginx-version", IngressNginxVersion, "Ingress Nginx Version")
	flag.StringVar(&cfg.CertManagerVersion, "cert-manager-version", CertManagerVersion, "Cert Manager Version")
	flag.StringVar(&cfg.NatsVersion, "nats-version", NatsVersion, "NATS Version")

	flag.Parse()
	return cfg
}

// detectNetwork handles interface detection and IP retrieval only.
// It relies on Packer/Netplan to have already configured the routes.
func detectNetwork(cfg *Config) error {
	log.Println("--- Network Detection ---")

	// Detect Interface
	iface, err := detectInterface()
	if err != nil {
		return err
	}
	cfg.Interface = iface
	log.Printf("Detected interface: %s", iface)

	// Ensure Interface is UP (Safety check)
	runCommand("ip", "link", "set", "dev", iface, "up")

	// Wait for IP (DHCP should have been handled by systemd-networkd)
	ip, err := waitForIP(iface)
	if err != nil {
		// Fallback: Try force DHCP if the baked config failed to grab an IP
		log.Println("No IP found, attempting dhclient fallback...")
		runCommand("dhclient", iface)
		ip, err = waitForIP(iface)
		if err != nil {
			return fmt.Errorf("failed to obtain IP: %v", err)
		}
	}
	cfg.PrivateIP = ip
	log.Printf("Private IP: %s", cfg.PrivateIP)

	return nil
}

func detectInterface() (string, error) {
	ifaces, err := net.Interfaces()
	if err != nil {
		return "", err
	}
	for _, i := range ifaces {
		// Look for standard ethernet names
		if strings.HasPrefix(i.Name, "eth") || strings.HasPrefix(i.Name, "en") {
			return i.Name, nil
		}
	}
	return "", fmt.Errorf("no ethernet interface found")
}

func waitForIP(iface string) (string, error) {
	for range 60 {
		ifaceObj, err := net.InterfaceByName(iface)
		if err == nil {
			addrs, _ := ifaceObj.Addrs()
			for _, addr := range addrs {
				// Check for IPv4
				if ipnet, ok := addr.(*net.IPNet); ok && !ipnet.IP.IsLoopback() {
					if ipnet.IP.To4() != nil {
						return ipnet.IP.String(), nil
					}
				}
			}
		}
		time.Sleep(1 * time.Second)
	}
	return "", fmt.Errorf("timeout waiting for IP")
}

// setupTailscale starts daemon, joins network, and retrieves Tailscale IP
func setupTailscale(cfg *Config) error {
	log.Println("--- Tailscale Setup ---")
	runCommand("systemctl", "start", "tailscaled")
	time.Sleep(2 * time.Second)

	tag := "tag:k3s-agent"
	if cfg.Role == "server" {
		tag = "tag:k3s-server"
	}

	if cfg.TailscaleTag != "" {
		tag = cfg.TailscaleTag
	}

	// Retry loop for join
	success := false
	for i := range maxRetries {
		err := runCommand("tailscale", "up", "--authkey="+cfg.TailscaleKey, "--ssh", "--hostname="+cfg.Hostname, "--advertise-tags="+tag, "--reset")
		if err == nil {
			success = true
			break
		}
		log.Printf("Tailscale join attempt %d failed. Retrying...", i+1)
		time.Sleep(retryInterval)
	}

	if !success {
		return fmt.Errorf("failed to join Tailscale after retries")
	}

	// Get Tailscale IP
	out, err := exec.Command("tailscale", "ip", "-4").Output()
	if err != nil {
		return err
	}
	cfg.TailscaleIP = strings.TrimSpace(string(out))
	log.Printf("Tailscale IP: %s", cfg.TailscaleIP)
	return nil
}

func generateK3sConfig(cfg *Config) (string, error) {
	configTmpl := `token: {{.K3sToken}}
node-ip: {{.PrivateIP}}
node-external-ip: {{.TailscaleIP}}
kubelet-arg:
  - "cloud-provider=external"
`
	if cfg.Role == "server" {
		configTmpl += `tls-san:
  - {{.Hostname}}
  - {{.TailscaleIP}}
  - {{.LBIP}}
flannel-backend: none
disable-network-policy: true
disable:
  - traefik
  - servicelb
  - cloud-controller
etcd-s3: true
etcd-s3-endpoint: storage.googleapis.com
etcd-s3-access-key: {{.EtcdS3Access}}
etcd-s3-secret-key: {{.EtcdS3Secret}}
etcd-s3-bucket: {{.EtcdS3Bucket}}
etcd-snapshot-schedule-cron: "0 */6 * * *"
etcd-snapshot-retention: 10
`
		if cfg.IsInit {
			configTmpl += "cluster-init: true\n"
		} else {
			configTmpl += fmt.Sprintf("server: https://%s:6443\n", cfg.LBIP)
		}

	} else {
		// Agent
		url := cfg.K3sURL
		if !strings.HasPrefix(url, "https://") {
			url = "https://" + url
		}
		configTmpl += fmt.Sprintf("server: %s\n", url)
	}

	t, err := template.New("k3s").Parse(configTmpl)
	if err != nil {
		return "", err
	}

	var buf bytes.Buffer
	if err := t.Execute(&buf, cfg); err != nil {
		return "", err
	}
	return buf.String(), nil
}

func configureK3s(cfg *Config) error {
	log.Println("--- K3s Configuration ---")

	// Note: Packer already created /etc/rancher/k3s with correct permissions

	content, err := generateK3sConfig(cfg)
	if err != nil {
		return err
	}

	return os.WriteFile(k3sConfigPath, []byte(content), 0600)
}

func startK3s(cfg *Config) error {
	svc := "k3s"
	if cfg.Role == "agent" {
		svc = "k3s-agent"
	}
	log.Printf("Starting service: %s", svc)
	runCommand("systemctl", "enable", svc)
	return runCommand("systemctl", "start", svc)
}

func waitForAPI(target string) error {
	log.Printf("Waiting for API at %s...", target)
	// Normalization logic
	url := target
	if !strings.HasPrefix(url, "https://") {
		url = "https://" + target
	}
	if !strings.HasSuffix(url, ":6443") && !strings.Contains(url, ":") {
		url += ":6443" // Assume port if missing and not a full URL
	}

	if !strings.Contains(url, "/") {
		url += "/healthz"
	} else if !strings.HasSuffix(url, "/healthz") {
		url += "/healthz"
	}

	client := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		},
		Timeout: 2 * time.Second,
	}

	for i := range maxRetries {
		resp, err := client.Get(url)
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				return nil
			}
			log.Printf("API check attempt %d: Status %d", i+1, resp.StatusCode)
		} else {
			log.Printf("API check attempt %d: %v", i+1, err)
		}
		time.Sleep(retryInterval)
	}
	return fmt.Errorf("API never became ready")
}

func finalizeTaints(cfg *Config) error {
	os.Setenv("KUBECONFIG", "/etc/rancher/k3s/k3s.yaml")

	// Wait for node to register
	for range 30 {
		if err := runCommand("kubectl", "get", "node", cfg.Hostname); err == nil {
			break
		}
		time.Sleep(2 * time.Second)
	}

	// Remove cloud provider taint
	runCommand("kubectl", "taint", "node", cfg.Hostname, "node.cloudprovider.kubernetes.io/uninitialized:NoSchedule-")

	// Dev environment specific: remove master taint
	if cfg.CloudEnv == "dev" {
		runCommand("kubectl", "taint", "node", cfg.Hostname, "node-role.kubernetes.io/master:NoSchedule-")
		runCommand("kubectl", "taint", "node", cfg.Hostname, "node-role.kubernetes.io/control-plane:NoSchedule-")
	}
	return nil
}

func writeManifests(cfg *Config) error {
	// Packer already created manifestDir, so we only need to write files.

	// Read all manifest files from embedded filesystem
	entries, err := manifestFS.ReadDir("manifests")
	if err != nil {
		return fmt.Errorf("failed to read manifest directory: %v", err)
	}

	// Sort entries to ensure consistent ordering
	sort.Slice(entries, func(i, j int) bool {
		return entries[i].Name() < entries[j].Name()
	})

	for _, entry := range entries {
		if !strings.HasSuffix(entry.Name(), ".yaml") {
			continue
		}

		log.Printf("Processing manifest: %s", entry.Name())

		// Read the manifest file
		manifestPath := "manifests/" + entry.Name()
		content, err := manifestFS.ReadFile(manifestPath)
		if err != nil {
			return fmt.Errorf("failed to read manifest %s: %v", entry.Name(), err)
		}

		// Parse and execute as Go template
		tmpl, err := template.New(entry.Name()).Parse(string(content))
		if err != nil {
			return fmt.Errorf("failed to parse template %s: %v", entry.Name(), err)
		}

		var buf bytes.Buffer
		if err := tmpl.Execute(&buf, cfg); err != nil {
			return fmt.Errorf("failed to execute template %s: %v", entry.Name(), err)
		}

		// Write the processed manifest
		outputPath := filepath.Join(manifestDir, entry.Name())
		if err := os.WriteFile(outputPath, buf.Bytes(), 0600); err != nil {
			return fmt.Errorf("failed to write manifest %s: %v", entry.Name(), err)
		}
	}

	return nil
}

func runCommand(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("command %s %v failed: %v\nOutput: %s", name, args, err, string(out))
	}
	return nil
}
