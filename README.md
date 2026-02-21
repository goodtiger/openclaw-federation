# OpenClaw Federation Deployment

> Multi-node OpenClaw federation deployment and management solution

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Overview

This project provides a complete solution for deploying and managing OpenClaw across multiple machines, forming a federated cluster where:

- **Master Node**: Central coordination hub
- **Worker Nodes**: Execution nodes with different skills (Docker, K8s, Apple Notes, etc.)
- **Tailscale Network**: Secure encrypted tunnel between all nodes
- **Platforms**: Linux/macOS/Raspberry Pi (mix and match for Master/Worker)

## Quick Start

```bash
# 1. Deploy Master
sudo ./bin/deploy-federation.sh master --bind-tailscale

# 2. Deploy Worker
sudo ./bin/deploy-federation.sh worker \
  --master-ip 100.64.0.1 \
  --token-file /root/.openclaw/.federation-token

# 3. Verify
./bin/manage-federation.sh list
```

If your system doesn't have `/root` (e.g. macOS), set `TOKEN_FILE` to a custom path.

## Directory Structure

```
.
├── bin/              # Core executable scripts
│   ├── deploy-federation.sh
│   ├── health-check.sh
│   ├── auto-register.sh
│   ├── config-center.sh
│   ├── switch-bind-mode.sh
│   ├── config-manager.sh
│   ├── manage-federation.sh
│   └── task-share.sh
│
├── docs/             # Documentation
│   ├── README.md
│   ├── FEDERATION_README.md
│   └── SAFE_DEPLOY_README.md
│
├── tests/            # Test scripts
│   └── test-*.sh
│
├── demos/            # Demo scripts
│   └── demo-*.sh
│
└── .gitignore
```

## Core Scripts

| Script | Purpose |
|--------|---------|
| `bin/deploy-federation.sh` | Deploy Master or Worker nodes |
| `bin/health-check.sh` | Monitor node health status |
| `bin/auto-register.sh` | Automatic node registration |
| `bin/config-center.sh` | Centralized configuration management |
| `bin/switch-bind-mode.sh` | Dynamic binding mode switch |
| `bin/config-manager.sh` | Config backup/restore |
| `bin/manage-federation.sh` | Node management |
| `bin/task-share.sh` | Task collaboration system |

## Documentation

- [Main Documentation](docs/README.md)
- [Federation Architecture](docs/FEDERATION_README.md)
- [Safe Deployment Guide](docs/SAFE_DEPLOY_README.md)

## Testing

```bash
# Run comprehensive tests
cd tests
bash test-complete.sh
```

## Demos

```bash
# View interactive demos
cd demos
bash demo-token-sharing.sh
bash demo-task-share.sh
```

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
