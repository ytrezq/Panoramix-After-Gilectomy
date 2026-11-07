# ZenStaker local devnet

One `docker compose` that brings up a complete local environment:

1. **anvil** — local EVM node (chain id `31337`) on `:8545`
2. **contracts** — one-shot job that deploys the stack with
   `script/DeployZenStakerTestnet.s.sol` (test ERC20 + IdentityEarningPowerCalculator
   + `ZenStaker`, deployed directly, no proxy)
3. **postgres + ipfs** — graph-node backing services
4. **graph-node** — indexer, pointed at anvil
5. **subgraph-deployer** — one-shot job that reads the freshly deployed ZenStaker
   address from the forge broadcast file, generates `subgraph.devnet.yaml` and
   deploys the subgraph to the local graph-node

The two one-shot jobs are ordered via compose conditions:
`contracts` waits for anvil to be healthy, and `subgraph-deployer` waits for
`contracts` to finish successfully **and** for graph-node to start. Both jobs are
idempotent: on a restart with persisted state they detect the
already-initialized chain / deployed subgraph and skip, keeping addresses stable.

All state is persisted under `data/` (anvil chain → `data/anvil`, index →
`data/postgres`, ipfs → `data/ipfs`), so the stack survives stop/restart.

## Requirements

- Docker + Docker Compose v2
- The Foundry git submodules present (`lib/forge-std`, `lib/openzeppelin-contracts`).
  If missing: `git submodule update --init --recursive` from the repo root.

## Run

From this `devnet/` folder:

```bash
docker compose up            # follow logs in the foreground
# or
docker compose up -d         # background
```

First run is slower: the foundry image downloads solc 0.8.28, graph-node
initializes its DB, and the subgraph dependencies install if needed.

When everything is up:

| Service          | URL                                                   |
| ---------------- | ----------------------------------------------------- |
| Anvil RPC        | http://localhost:8545                                 |
| GraphQL          | http://localhost:8000/subgraphs/name/zen-staker       |
| Graph admin RPC  | http://localhost:8020                                 |

Find the deployed addresses (token, calculator, staker) in the logs of the
`contracts` service, or in
`broadcast/DeployZenStakerTestnet.s.sol/31337/run-latest.json`.

## Exercise the contracts

The deploy script only **deploys** the `ERC20VotesMock` token — it does **not**
mint any, so `totalSupply` starts at `0`. Helper scripts to mint test tokens and
start a reward distribution live in [`test_scripts/`](test_scripts/) — they read
the deployed addresses from the broadcast file automatically. Quick start:

```bash
cd test_scripts
./mint.sh                 # mint 10 GOV to the admin (anvil account #3)
./set-reward.sh           # start a 100 GOV reward over REWARD_DURATION (30d)
```

See [`test_scripts/README.md`](test_scripts/README.md) for arguments and options.

## Stop / reset

State (chain, index, ipfs) persists under `data/`, so you can stop and resume
without losing anything:

```bash
docker compose stop          # stop containers, keep all state
docker compose up            # resume where you left off (jobs skip redeploy)
docker compose down          # remove containers + networks, keep state in data/
```

`anvil` dumps its state to `data/anvil/anvil-state.json` on shutdown (and every
5s as a guard) and reloads it on boot; graph-node resumes indexing from the
persisted postgres data on its own.

For a clean slate, wipe the persisted state (note: the `postgres` dir is
root-owned, so this needs `sudo`):

```bash
docker compose down
sudo rm -rf data/            # wipe anvil chain + postgres + ipfs state
```

Wipe all-or-nothing — removing only part of `data/` leaves the subgraph indexing
a chain that no longer matches. (`docker compose down -v` removes named volumes
only; it does **not** touch the `data/` bind mounts.)

## Notes

- The deployer uses anvil's default account #3
  (`0x7c8521...`, address `0x90F7...`) — a publicly known, pre-funded dev key.
  Never use it outside a local devnet.
- `network: mainnet` in the generated manifest is just the label that matches
  graph-node's `ethereum` env var; the underlying chain is anvil (31337).
- `anvil --block-time 2` keeps the chain head advancing so graph-node keeps
  indexing. Send transactions via `cast` against `:8545` to exercise the
  contracts and watch entities appear in the GraphQL playground.
- The `contracts` and `subgraph-deployer` jobs run as UID/GID `1000` by default
  so files written into the mounted repo stay owned by you. Override with
  `DEVNET_UID` / `DEVNET_GID` if your host user differs:
  `DEVNET_UID=$(id -u) DEVNET_GID=$(id -g) docker compose up`.
```
