# OpenClaw Federation Deployment

> Multi-node OpenClaw federation deployment and management solution

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Overview

This project provides a complete solution for deploying and managing OpenClaw across multiple machines, forming a federated cluster where:

- **Master Node**: Central coordination hub
- **Worker Nodes**: Execution nodes with different skills (Docker, K8s, Apple Notes, etc.)
- **Tailscale Network**: Secure encrypted tunnel between all nodes

## Features

### Core Features
- ✅ **Automated Deployment**: One-command deployment for Master and Worker nodes
- ✅ **Token Sharing**: Secure cross-machine authentication
- ✅ **Configuration Preservation**: Safely merges new config with existing settings
- ✅ **Flexible Binding**: Choose between 0.0.0.0 (convenient) or Tailscale IP (secure)

### Advanced Features
- 🔍 **Health Check**: Monitor node status with automatic alerting
- 📝 **Auto-Register**: Workers automatically register with Master
- ⚙️ **Config Center**: Centralized configuration management and sync
- 🔄 **Bind Mode Switch**: Dynamically switch binding mode on Workers
- 📋 **Task Sharing**: Collaborative task system between Master and Workers

## Quick Start

### Prerequisites
- All machines have OpenClaw installed
- All machines joined the same Tailscale network
- Root/sudo access

### 1. Deploy Master

```bash
# Secure mode (recommended)
sudo ./deploy-federation.sh master --bind-tailscale

# Or default mode
sudo ./deploy-federation.sh master
```

Save the displayed Token!

### 2. Deploy Workers

```bash
sudo ./deploy-federation.sh worker \
  --master-ip 100.64.0.1 \
  --token "YOUR_TOKEN_HERE" \
  --node-name "worker1"
```

### 3. Verify

```bash
# On Master
openclaw nodes list
openclaw nodes invoke worker1 -- uname -a
```

## File Structure

```
.
├── deploy-federation.sh      # Core deployment script
├── health-check.sh           # Node health monitoring
├── auto-register.sh          # Automatic node registration
├── config-center.sh          # Configuration management
├── switch-bind-mode.sh       # Dynamic binding mode switch
├── config-manager.sh         # Config backup/restore
├── manage-federation.sh      # Node management
├── task-share.sh             # Task collaboration system
├── README.md                 # This file
└── tests/                    # Test scripts
```

## Usage Examples

### Example 1: Deploy Nginx on Worker

```bash
# On Master
openclaw nodes invoke worker1 -- docker run -d -p 80:80 nginx
```

### Example 2: Create Note on Mac Worker

```bash
openclaw nodes invoke mac-mini -- \
  openclaw skill apple-notes \
  --title "Shopping List" \
  --body "1. Milk\n2. Eggs"
```

### Example 3: Collaborative Task

```bash
# Master creates task
./task-share.sh create "Backup Database" worker2 high "Daily backup"

# Worker claims and executes
./task-share.sh claim worker2
./task-share.sh update task-xxx 50 "Exporting data..."
./task-share.sh complete task-xxx "Backup completed"
```

## Documentation

- [Safe Deployment Guide](SAFE_DEPLOY_README.md)
- [Federation Architecture](FEDERATION_README.md)
- [Auto Updater Guide](UPDATER_NOTIFY_README.md)

## Testing

```bash
# Run comprehensive tests
bash test-complete.sh

# View demos
bash demo-token-sharing.sh
bash demo-task-share.sh
```

## Security

- 🔐 Token-based authentication
- 🔒 Tailscale encrypted networking
- 🛡️ Automatic configuration backup
- 📝 Detailed audit logs

## License

MIT License - see [LICENSE](LICENSE) file for details

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Support

- 📖 Check the documentation in `README*.md` files
- 🎬 Run `demo-*.sh` scripts for interactive examples
- 🧪 Use `test-*.sh` scripts to verify functionality

---

**Note**: This is a community project for OpenClaw federation deployment. Use at your own risk in production environments.
