# Project Platform (Experimental) 🧪

**A learning journey into building cloud-native infrastructure for Go.**

Project Platform is an experimental project where we are exploring how to build a hosting environment for Go applications. It is not a finished product, but a sandbox for learning about Kubernetes, serverless patterns, and infrastructure-as-code.

> [!IMPORTANT]  
> **Learning Project:** This is a work in progress and is currently used for educational purposes. It is not intended for production use. We are figuring things out as we go!

## 🎯 Learning Goals

- **Go & Kubernetes:** Understanding how to build and orchestrate Go services effectively.
- **Serverless Patterns:** Experimenting with Knative for "scale to zero" and event-driven architectures.
- **Infrastructure as Code:** Practicing with Terraform, Packer, and Task to manage complex setups.
- **Security Sandboxing:** Learning about gVisor, KubeArmor, and Kyverno for hardening workloads.
- **Observability:** Setting up and tuning the VictoriaMetrics, Loki, Grafana, and Fluent Bit stack.
- **GitOps:** ArgoCD for declarative application management.

## 🛠 Experimental Stack

This stack represents what we are currently playing with:

### Backend & API
- **Language:** Go 1.22+
- **Build Tools:** [ko](https://github.com/ko-build/ko) and Docker
- **API Framework:** [ConnectRPC](https://connectrpc.com/docs/go/) (Protobuf)
- **Database:** PostgreSQL (CloudNativePG)
- **Auth:** WorkOS (OIDC)

### Infrastructure
- **Orchestration:** Talos Linux
- **Provisioning:** Terraform & Packer
- **Providers:** Hetzner (Bare Metal)
- **Serverless:** Knative Serving & Eventing
- **GitOps:** ArgoCD
- **Security:** gVisor, KubeArmor, Kyverno
- **Networking:** Cilium & NATS

## 🏗 Project Structure

```text
.
├── core/                # Go API & CLI Logic
│   ├── cmd/             # Entry points
│   ├── internal/        # Private application code
│   └── pkg/             # SDK experiments
├── database/            # Migrations & SQLC
├── infra/               # IaC experiments
│   ├── packer/          # Image builds
│   ├── platform/        # Kubernetes manifests
│   └── terraform/       # Cloud resources
├── web/                 # Next.js
└── Runbook.md           # Operational notes
```

## 🚀 Running Locally

If you want to poke around the project:

1. **Clone the repo:**
   ```bash
   git clone https://github.com/kendricklawton/project-platform.git
   cd project-platform
   ```

2. **Setup Environment:**
   Copy `.env.example` to `.env` and add your local/dev credentials.

3. **Local DB:**
   ```bash
   task db:setup
   ```

4. **Run the API:**
   ```bash
   task dev:api
   ```

## 📖 Notes
- See [Runbook.md](./Runbook.md) for how we are thinking about operating this.
- This project is a messy work-in-progress—expect things to break!

---
*Just learning by doing.*
