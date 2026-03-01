# Project Platform (Experimental) 🧪

**A learning journey into building cloud-native infrastructure for Go.**

Project Platform is an experimental project where we are exploring how to build a hosting environment for Go applications. It is not a finished product, but a sandbox for learning about Kubernetes, serverless patterns, and infrastructure-as-code.

> [!IMPORTANT]  
> **Learning Project:** This is a work in progress and is currently used for educational purposes. It is not intended for production use. We are figuring things out as we go!

## 🎯 Learning Goals

- **Go & Kubernetes:** Understanding how to build and orchestrate Go services effectively.
- **Immutable Infrastructure:** Using Packer to build hardened "Golden Images" for instant Terraform scaling.
- **Private Networking & Security:** Securing cluster access with Tailscale and hardening workloads with gVisor, KubeArmor, and Kyverno.
- **Serverless Patterns:** Experimenting with Knative for "scale to zero" and event-driven architectures.
- **Observability:** Setting up and tuning the VictoriaMetrics, Loki, Grafana, and Fluent Bit stack.
- **GitOps:** ArgoCD and Sealed Secrets for secure declarative application management.

## 🛠 Experimental Stack

This stack represents what we are currently playing with:

### Backend & API
- **Language:** Go 1.22+
- **Build Tools:** [ko](https://github.com/ko-build/ko),Docker, & Potential Buildpacks
- **API Framework:** [ConnectRPC](https://connectrpc.com/docs/go/) (Protobuf)
- **Database:** PostgreSQL (CloudNativePG)
- **Auth:** WorkOS (OIDC)

### Frontend
- **Markup:** Go + [HTMX](https://htmx.org/)
- **Styling:** [Tailwind CSS](https://tailwindcss.com/)
- **Interactivity:** [Alpine.js](https://alpinejs.dev/)

### Infrastructure
- **Operating System:** Ubuntu Linux (Immutable Golden Images)
- **Orchestration:** K3s
- **Provisioning:** Terraform & Packer
- **Providers:** Hetzner Cloud (Primary) & DigitalOcean
- **Serverless:** Knative Serving & Eventing
- **GitOps:** ArgoCD
- **Security & Networking:** Tailscale, Cilium, NATS, gVisor, KubeArmor, Kyverno

## 🏗 Project Structure

```text
.
├── core/                # Go Monorepo
│   ├── cmd/             # Entry points (platform-server, platform-web, platform-worker, etc.)
│   ├── internal/        # Private application code & HTMX templates
│   ├── migrations/      # Database migrations
│   └── pkg/             # SDK experiments
├── infrastructure/      # IaC experiments
│   ├── packer/          # Golden Image builds (Ubuntu + K3s + Tailscale)
│   ├── argocd/          # Kubernetes manifests & ArgoCD Apps
│   └── terraform/       # Cloud resources & cluster bootstrapping
├── proto/               # Protobuf definitions
└── RUNBOOK.md           # Operational notes
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

4. **Run the Local Services:**
   In separate terminal windows, run the following:
   ```bash
   # Run the Core API Server
   task dev:api

   # Run the Background Worker
   task dev:worker

   # Run the HTMX Web Frontend
   task dev:web
   ```

## 📖 Notes
- See [RUNBOOK.md](./RUNBOOK.md) for how we are thinking about operating this.
- This project is a messy work-in-progress—expect things to break!

---
*Just learning by doing.*
