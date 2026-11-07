# KAT LayerZero OFT Upgradeable

Cross-chain KAT token using LayerZero V2 with upgradeable proxy contracts.

## Overview

**Contracts:**
- `KATCustomOFTAdapterUpgradeable` — OFT Adapter on Katana (wraps native KAT)
- `KATOFTUpgradeable` — Standard OFT on Ethereum, Base, Arbitrum, Polygon

**Deploy scripts:**
- `deploy/KATOFTAdapterUpgradeable.ts` — Deploy OFT Adapter on Katana
- `deploy/KATOFTUpgradeableEVM.ts` — Deploy standard OFT on any EVM chain
- `deploy/upgradeCustomToStandardOFTAdapter.ts` — Upgrade Katana Adapter to standard implementation
- `deploy/upgradeCustomToStandardOFT.ts` — Upgrade OFT to standard implementation

## Deployments

See [DEPLOYMENTS.md](./DEPLOYMENTS.md) for all mainnet contract addresses (Katana, Ethereum, Base).

## Setup

```bash
pnpm install
cp .env.example .env
```

Required `.env` values:
```
PRIVATE_KEY=0x...          # or MNEMONIC="..."
KAT_TOKEN_ADDRESS=0x...    # KAT token on Katana
ETHERSCAN_API_KEY=...
```

RPC URLs default to public nodes but can be overridden:
```
RPC_URL_KATANA_MAINNET=https://rpc.katana.network
RPC_URL_ETHEREUM_MAINNET=https://ethereum-rpc.publicnode.com
RPC_URL_BASE_MAINNET=https://base-rpc.publicnode.com
RPC_URL_ARBITRUM_MAINNET=https://arbitrum-one-rpc.publicnode.com
RPC_URL_POLYGON_MAINNET=https://polygon-bor-rpc.publicnode.com
```

## Compile

```bash
pnpm compile
```

## Deploy

**OFT Adapter (Katana):**
```bash
pnpm hardhat lz:deploy --tags KATCustomOFTAdapterUpgradeable
```

**Standard OFT (any EVM chain):**
```bash
pnpm hardhat deploy --tags KATOFTUpgradeable --network <network-name>
# e.g. ethereum-mainnet | base-mainnet | arbitrum-mainnet | polygon-mainnet
```

Deploys proxy + ProxyAdmin + implementation. Deployer is the initial owner — transfer to Safe after wiring (see [Ownership Transfer](#ownership-transfer)).

## Verify Contracts

```bash
npx @layerzerolabs/verify-contract@latest --network <network-name> --deployments deployments --api-key YOUR_ETHERSCAN_API_KEY
```

## Wire OApp

Sets peers, DVNs, executors, and enforced options as defined in `layerzero.config.ts`.

**Live run:**
```bash
pnpm hardhat lz:oapp:wire --oapp-config layerzero.config.ts
```

**Dry-run** (preview only, prints to stdout — no submission):
```bash
pnpm hardhat lz:oapp:wire --oapp-config layerzero.config.ts --dry-run
```

**Write transactions to JSON file** (for Safe submission — without executing on-chain):
```bash
pnpm hardhat lz:oapp:wire --oapp-config layerzero.config.ts --output-filename wire-txns.json --skip-connections-from-eids <eids-to-skip>
```

When prompted:
- `Preview transactions? (Y/n)` → press `n`
- `Send transactions? (Y/n)` → press `n`

The JSON file is written before the prompts, so pressing `n` both times saves the file without submitting anything on-chain.

> **Note:** `--output-filename` has no effect with `--dry-run` — the file write happens inside `signAndSend`, which dry-run bypasses entirely.

**Wiring by signer** — when chains have different owners (deployer vs Safe), split by EID:
```bash
# Deployer-signed chains only (e.g. Ethereum side) — submits directly
pnpm hardhat lz:oapp:wire --oapp-config layerzero.config.ts --skip-connections-from-eids 30375,30102

# Safe-signed chains only (e.g. Katana side) — write to file, press n at both prompts, submit via Safe UI
pnpm hardhat lz:oapp:wire --oapp-config layerzero.config.ts --output-filename katana-wire-txns.json --skip-connections-from-eids 30101,30102
```

## Inspect Peers

```bash
pnpm hardhat lz:oapp:peers:get --oapp-config layerzero.config.ts
```

## Send OFT Tokens

```bash
pnpm hardhat lz:oft:send \
  --network <src-network> \
  --src-eid <src-eid> \
  --dst-eid <dst-eid> \
  --amount <amount> \
  --to <receiver_address> \
  --oft-address <oft_contract_address>
```

| Route | `--src-eid` | `--dst-eid` | `--network` |
|---|---|---|---|
| Katana → Ethereum | 30375 | 30101 | `katana-mainnet` |
| Ethereum → Katana | 30101 | 30375 | `ethereum-mainnet` |
| Katana → Base | 30375 | 30184 | `katana-mainnet` |
| Base → Katana | 30184 | 30375 | `base-mainnet` |
| Ethereum → Base | 30101 | 30184 | `ethereum-mainnet` |
| Base → Ethereum | 30184 | 30101 | `base-mainnet` |

Track cross-chain messages on [LayerZero Scan](https://layerzeroscan.com/).

**Generate Safe batch payload** (approve + send) for multi-sig wallets:
```bash
pnpm hardhat lz:oft:encode-safe-send \
  --network <src-network> \
  --src-eid <src-eid> \
  --dst-eid <dst-eid> \
  --amount <amount> \
  --to <receiver_address> \
  --safe-address <safe_address> \
  --oft-address <oft_contract_address>
```

## Upgrade Contracts

**Upgrade OFT Adapter (Katana):**
```bash
pnpm hardhat deploy --tags upgradeCustomToStandardOFTAdapter --network katana-mainnet
```
Deploys the new implementation and prints the `ProxyAdmin.upgrade()` calldata to submit via Safe.

**Upgrade OFT (BSC):**
```bash
pnpm hardhat deploy --tags upgradeCustomToStandardOFT --network bsc-mainnet
```

## Ownership Transfer

After wiring is verified, transfer the OFT proxy owner and ProxyAdmin owner to the Safe multisig:

```bash
cast send <PROXY_ADDRESS> "transferOwnership(address)" <SAFE_ADDRESS> \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY

cast send <PROXY_ADMIN_ADDRESS> "transferOwnership(address)" <SAFE_ADDRESS> \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

## Configuration

| Network | EID | Chain ID |
|---|---|---|
| Katana | 30375 | 747474 |
| Ethereum | 30101 | 1 |
| Base | 30184 | 8453 |
| Arbitrum | 30110 | 42161 |
| Polygon | 30109 | 137 |
| BSC | 30102 | 56 |

`layerzero.config.ts` — pathway definitions, DVN security settings, enforced gas options.

## Testing

```bash
pnpm test              # Run all tests
pnpm test:hardhat      # Hardhat tests only
pnpm test:forge        # Forge tests only
```

## Security

**Audits:**
- [Hexens - January 2026](audits/hexens_audit_jan2026.pdf)

## Resources

- [LayerZero V2 Docs](https://docs.layerzero.network/v2)
- [OFT Standard](https://docs.layerzero.network/v2/concepts/applications/oft-standard)
- [Deployed Endpoints](https://docs.layerzero.network/v2/deployments/deployed-contracts)
- [LayerZero Scan](https://layerzeroscan.com/)

## License

MIT
