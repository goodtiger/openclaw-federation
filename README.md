# OpenClaw Federation Scripts

A collection of utility scripts for deploying and managing OpenClaw Federation nodes.

## Scripts Overview

### 1. Deploy Federation (`bin/deploy-federation.sh`)
This is the primary script for setting up a new OpenClaw node. It handles installation, configuration, and joining a federation.

**Usage:**
```bash
# Basic deployment (interactive)
./bin/deploy-federation.sh

# Deploy as Master (Gateway)
./bin/deploy-federation.sh --role master --token <your-token>

# Deploy as Worker (Node)
./bin/deploy-federation.sh --role worker --master-url <master-url> --token <token>
```

### 2. Manage Federation (`bin/manage-federation.sh`)
A utility for managing the federation state, checking status, and performing maintenance tasks on an existing installation.

**Usage:**
```bash
./bin/manage-federation.sh [command]

# Common commands:
# status   - Show current node status
# restart  - Restart OpenClaw services
# update   - Update OpenClaw to latest version
```

### 3. Auto Register (`bin/auto-register.sh`)
Helper script to automatically approve pending worker nodes on the Master gateway. Useful for automated deployments.

**Usage:**
```bash
# Run on Master node
./bin/auto-register.sh
```

## Architecture

- **Master (Gateway):** The central control plane. Manages task distribution and worker coordination.
- **Worker (Node):** Executes tasks. Connects to the Master via secure tunnel (Tailscale/WireGuard).
- **Hybrid:** A node can function as both Master and Worker for smaller deployments.

## Prerequisites

- Ubuntu/Debian based system
- Root or sudo access
- Internet connection for fetching dependencies
