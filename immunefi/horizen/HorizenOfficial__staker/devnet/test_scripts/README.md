# devnet test scripts

Small helpers to exercise the running local devnet. They read the deployed
addresses straight from the forge broadcast file
(`broadcast/DeployZenStakerTestnet.s.sol/31337/run-latest.json`), so bring the
devnet up first (`docker compose up` from `devnet/`).

Requires `cast` (Foundry) and one of `jq` / `python3` / `node` on the host.

| Script           | What it does                                                        |
| ---------------- | ------------------------------------------------------------------- |
| `mint.sh`        | Public-mint GOV test tokens to an address.                          |
| `set-reward.sh`  | Authorize notifier → fund staker → `notifyRewardAmount` (30d window). |

## Usage

```bash
cd devnet/test_scripts

# Mint 1,000,000 GOV to the admin (anvil account #3)
./mint.sh

# Mint a custom amount to a custom address
./mint.sh 0xYourAddress 5000

# Start a 1,000,000 GOV reward distribution over REWARD_DURATION (30 days)
./set-reward.sh

# ...or a custom amount
./set-reward.sh 250000
```

All config has env-var overrides (`RPC_URL`, `PRIVATE_KEY`, `ADMIN`) — see
`_common.sh`. Defaults target the local anvil node on `:8545` with anvil's
default account #3 (the devnet deployer / staker admin).
