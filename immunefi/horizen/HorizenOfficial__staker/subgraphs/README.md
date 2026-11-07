# ZenStaker Subgraph

## Requirements
- Node.js + npm or yarn.
- A Goldsky account with an API key.

## Install Goldsky CLI and log in
Official guide: https://docs.goldsky.com/subgraphs/deploying-subgraphs#install-goldskys-cli-and-log-in

macOS/Linux:
```bash
curl https://goldsky.com | sh
```

Windows:
```bash
npm install -g @goldskycom/cli
```

Log in with your API key:
```bash
goldsky login
goldsky
```

## Install The Graph CLI
Official guide: https://thegraph.com/docs/en/subgraphs/developing/creating/install-the-cli/
For subgraph creation and general workflow, follow The Graph documentation:
https://thegraph.com/docs/en/subgraphs/

Using npm:
```bash
npm install -g @graphprotocol/graph-cli@latest
```

Using yarn:
```bash
yarn global add @graphprotocol/graph-cli
```

## Generate and build the subgraph
Edit the file: <br/>
subgraphs/subgraph.yaml <br/>
(replace <contract_address> in *dataSources.source.address* with the address of the deployed **ZenStaker** contract)<br/>

From this directory:
```bash
npm i
graph codegen
graph build
```

## Deploy to Goldsky
Guide: https://docs.goldsky.com/chains/horizen#install-goldskys-cli-and-log-in
For deployment details and options, follow the Goldsky documentation:
https://docs.goldsky.com/subgraphs/

```bash
goldsky subgraph deploy <name>/<version> --path .
```

## Stable URL with tags (alias)
Goldsky supports tags to keep a stable endpoint between deploys.

Create a tag (first release):
```bash
goldsky subgraph tag create <name>/<version> --tag prod
```

Stable endpoint:
```
https://api.goldsky.com/api/public/<PROJECT_ID>/subgraphs/<name>/prod/gn
```

Update the tag to point to a new version:
```bash
goldsky subgraph deploy <name>/<new-version> --path .
goldsky subgraph tag create <name>/<new-version> --tag prod
```

## Local development (without Goldsky)

`docker-compose.yml` spins up a full local Graph Node stack (graph-node + IPFS + Postgres) so you can iterate without touching any hosted service.

Requirements: Docker + Docker Compose, and a local Ethereum node (e.g. Anvil) listening on `http://host.docker.internal:8545`.

```bash
# 1. Start the local stack
docker compose up -d

# 2. Create the subgraph slot on the local node
npm run create-local

# 3. Deploy to the local node (re-run after any schema/mapping change)
npm run deploy-local

# GraphQL playground: http://localhost:8000/subgraphs/name/zen-staker
```

To stop and remove the stack:
```bash
docker compose down -v   # -v removes named volumes (clears indexed data)
```
