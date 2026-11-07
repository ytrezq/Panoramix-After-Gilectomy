# SwapVM Deployment Guide

This guide describes how to deploy SwapVM contracts using the Makefile-based deployment system.

## Prerequisites

Before deploying, ensure you have the following installed:

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (includes `forge`, `cast`, and `anvil`)
- Make (usually pre-installed on Unix systems)
- jq (JSON processor for parsing deployment outputs)
- A funded wallet for gas fees

## Quick Start

```bash
# 1. Copy and configure environment file
cp .env.example .env

# 2. Set required environment variables
# Edit .env file with your values

# 3. Deploy standard SwapVMRouter
make deploy-swap-vm

# 4. Get SwapVMRouter deployment address
make get PARAMETER=OPS_SWAP_VM_ROUTER_ADDRESS
```

## Environment Configuration

The deployment system uses environment variables that can be configured in two ways:

### Manual Mode (Default)
Create a `.env` file in the project root with the following variables:

```bash
# Network Configuration
OPS_NETWORK="localhost"          # Network name (e.g., mainnet, sepolia, localhost)
OPS_CHAIN_ID="31337"            # Chain ID for the target network

# Contract Parameters
OPS_AQUA_ADDRESS="0x..."        # Address of the Aqua contract
OPS_SWAP_VM_ROUTER_NAME="SwapVMRouter"
OPS_SWAP_VM_ROUTER_VERSION="1.0.0"

# Network-specific RPC and Private Key
# Format: <NETWORK_NAME>_RPC_URL and <NETWORK_NAME>_PRIVATE_KEY
LOCALHOST_RPC_URL=http://127.0.0.1:8545
LOCALHOST_PRIVATE_KEY=0x...

# For other networks, add corresponding entries:
# MAINNET_RPC_URL="https://eth-mainnet.g.alchemy.com/v2/YOUR-KEY"
# MAINNET_PRIVATE_KEY="0x..."
# SEPOLIA_RPC_URL="https://eth-sepolia.g.alchemy.com/v2/YOUR-KEY"
# SEPOLIA_PRIVATE_KEY="0x..."
```

### Automation Mode (Automated deployment framework)
For automated deployments .env.automation file will be created automatically and deployment is launched with:

```bash
OPS_LAUNCH_MODE=auto make deploy-swap-vm
```

## Configuration File

The `config/constants.json` file stores deployment parameters per chain:

```json
{
  "aqua": {
    "31337": "0x...",
    "1": "0x...",      // Mainnet address
    "11155111": "0x..." // Sepolia address
  },
  "swapVmRouterVersion": {
    "31337": "1.0.0"
  },
  "swapVmRouterName": {
    "31337": "SwapVMRouter"
  }
}
```

## Deployment Commands

### Main Deployment Targets

| Command | Description | Contract |
|---------|-------------|----------|
| `make deploy-swap-vm` | Deploy standard SwapVMRouter | SwapVMRouter.sol |
| `make deploy-swap-vm-aqua` | Deploy Aqua AMM SwapVMRouter | AquaSwapVMRouter.sol |
| `make deploy-swap-vm-limit` | Deploy Limit Orders SwapVMRouter | LimitSwapVMRouter.sol |

### Deployment Artifacts

Deployment information is saved in:
- `broadcast/` - Forge deployment transactions
- `deployments/<network>/` - Organized deployment files per network

## Helper Commands

### Development Tools

| Command | Description |
|---------|-------------|
| `make build` | Compile all contracts |
| `make tests` | Run test suite with gas reporting |
| `make coverage` | Generate code coverage report |
| `make snapshot` | Create gas snapshot |
| `make format` | Format code using Forge formatter |
| `make lint` | Check code formatting |
| `make clean` | Clean build artifacts |

### Local Development

Start local Anvil fork:
```bash
make anvil NODE_URL=<your-rpc-url>
```

Define correct env variables:

```bash
# define your network alias (e.g. localhost)
OPS_NETWORK="localhost"
# Use 31337 for local development
OPS_CHAIN_ID="31337"

# RPC URL for localhost network
LOCALHOST_RPC_URL=http://localhost:8546
# Replace with your own private key for localhost testing
LOCALHOST_PRIVATE_KEY=0x
```
