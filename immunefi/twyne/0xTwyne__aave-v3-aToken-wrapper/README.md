# Aave V3 aToken Wrapper

ERC4626-compliant wrapper for Aave V3 aTokens, converting rebasing tokens to non-rebasing shares for use as collateral in lending protocols.

## Overview

This wrapper allows collateral vaults to hold non-rebasing shares while the underlying aTokens continue to rebase. It includes special functions for collateral vaults to rebalance aToken positions for direct borrowing from Aave.

The contract inherits from Aave's StataTokenV2 and adds UUPS upgradeability along with custom collateral vault functions.

## Setup

Install dependencies and set up environment:

```sh
forge install
```
```sh
cp .env.example .env
```

## Running Tests

Run all tests (FFI required for TestnetProcedures):
```sh
FOUNDRY_PROFILE=mainnet forge test --ffi
```

Run specific test function:
```sh
FOUNDRY_PROFILE=mainnet forge test --match-test test_claimReward --ffi -vv
```

## Deployment

### Prerequisites

1. Ensure `TwyneAddresses_output.json` exists with the collateral vault factory address
2. Configure `.env` file with:
   - `DEPLOYER_ADDRESS`: Address of the deployer
   - `ADMIN_ETH_ADDRESS`: Multisig address that will own the contracts
   - `ETHERSCAN_API_KEY`: For contract verification on Ethereum mainnet

### Deploy to Mainnet

Deploy the wrapper behind a UUPS proxy:

```sh
forge script script/DeployAaveV3ATokenWrapper.s.sol:DeployAaveV3ATokenWrapper \
  --slow \
  --broadcast \
  --verify \
  --verifier etherscan \
  --etherscan-api-key <YOUR_ETHERSCAN_API_KEY>
```

### Deploy to Base

For Base deployment, update the verifier URL:

```sh
forge script script/DeployAaveV3ATokenWrapper.s.sol:DeployAaveV3ATokenWrapper \
  --slow \
  --broadcast \
  --verify \
  --verifier etherscan \
  --etherscan-api-key <YOUR_ETHERSCAN_API_KEY>
```

## Upgrading the Contract

To upgrade the UUPS proxy implementation:

```sh
forge script script/UpgradeAaveV3ATokenWrapper.s.sol:UpgradeAaveV3ATokenWrapper \
  --sig "run(address)" <PROXY_ADDRESS> \
  --slow \
  --broadcast \
  --verify \
  --verifier etherscan \
  --etherscan-api-key <YOUR_ETHERSCAN_API_KEY>
```

## Post-Deployment Verification

After deployment, verify everything is configured correctly:

```sh
forge script script/PostDeploymentCheck.s.sol:PostDeploymentCheck \
  --sig "run(address)" <PROXY_ADDRESS> \
  -vv
```

The script will verify:
- Proxy deployment and initialization
- Ownership configuration
- Collateral vault factory integration
- EVC integration
- Aave protocol integration
- ERC4626 compliance
- Access control for collateral vault functions