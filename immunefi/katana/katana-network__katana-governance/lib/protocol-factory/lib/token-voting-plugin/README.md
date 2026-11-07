# Token Voting Plugin [![Foundry][foundry-badge]][foundry] [![License: AGPL v3][license-badge]][license]

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg
[license]: https://opensource.org/licenses/AGPL-v3
[license-badge]: https://img.shields.io/badge/License-AGPL_v3-blue.svg

## Audit

### v1.4

**Halborn**: [audit report](./audits/halborn-audit-1-4.pdf)

- Commit ID: [aa4445a3b2b421feeed33ad000c7a0e7312f3817](https://github.com/aragon/token-voting-plugin/commit/aa4445a3b2b421feeed33ad000c7a0e7312f3817)
- Started: July 11th, 2025
- Finished: July 14th, 2025

### v1.3

TokenVoting v1.4 has been ported to Foundry.

The HardHat codebase of version 1.3 and earlier can be found [in this repo](https://github.com/aragon/token-voting-plugin-hardhat).

**Halborn**: [audit report](https://github.com/aragon/osx/tree/main/audits/Halborn_AragonOSx_v1_4_Smart_Contract_Security_Assessment_Report_2025_01_03.pdf)

- Commit ID: [02a7dbb95c42ebd2226117bf85a0fe330c788948](https://github.com/aragon/token-voting-plugin-hardhat/commit/02a7dbb95c42ebd2226117bf85a0fe330c788948)
- Started: 2024-11-18
- Finished: 2025-02-13

<!--
## ABI and artifacts

Check out the [artifacts folder](./packages/artifacts/README.md) to get the deployed addresses and the contract ABI's.
-->

## Features

TokenVoting is an Aragon OSx Plugin, designed to conduct governance processes where the voting power of each member is determined by an [IVotes compatible token](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/utils/IVotes.sol).

Three voting modes:
- Early execution: Execute when there's mathematical certainty that the proposal can't be defeated
- Vote replacement: Allow to change votes until the proposal ends
- Standard mode: No vote replacement or early execution.

Two token contracts are provided for convenience:
- GovernanceERC20: Mint a new token with a predefined set of addresses to mint for
- GovernanceWrappedERC20: Wrap an existing token that does not support [IVotes](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/utils/IVotes.sol) by itself

If you already have an IVotes compatible token, you can simply import it.

Other features:
- Excluding balances from certain accounts (non-circulating supply, e.g. vaults, the DAO's own holdings, etc)
- Mint freezing
- Granular permission management for proposal creation, proposal execution, token minting
- Minimum balance requirements for proposers

## Project structure

```
├── LICENSE
├── Makefile
├── foundry.toml
├── remappings.txt
├── script
│   ├── DeployPluginRepo.s.sol
│   ├── make-test-tree.ts
│   └── verify-contracts.sh
├── src
│   ├── TokenVoting.sol
│   ├── TokenVotingSetup.sol
│   ├── TokenVotingSetupZkSync.sol
│   ├── base
│   │   ├── IMajorityVoting.sol
│   │   └── MajorityVotingBase.sol
│   ├── condition
│   │   └── VotingPowerCondition.sol
│   └── erc20
│       ├── GovernanceERC20.sol
│       ├── GovernanceWrappedERC20.sol
│       ├── IERC20MintableUpgradeable.sol
│       └── IGovernanceWrappedERC20.sol
└── test
```

## Prerequisites
- [Foundry](https://getfoundry.sh/)
- [Make](https://www.gnu.org/software/make/)

Optional:

- [Docker](https://www.docker.com) (recommended for deploying)
- [Deno](https://deno.land)  (used to scaffold the test files)

## Getting Started

To get started, clone this repository and initialize it:

```bash
cp .env.example .env
make init
```

Edit `.env` to match your desired network and settings.

### Using the Makefile

The `Makefile` is the target launcher of the project. It's the recommended way to operate the repository. It manages the env variables of common tasks and executes only the steps that need to be run.

```
$ make
Available targets:

- make help               Display the available targets

- make init               Check the dependencies and prompt to install if needed
- make clean              Clean the build artifacts

Testing lifecycle:

- make test               Run unit tests, locally
- make test-fork          Run fork tests, using RPC_URL
- make test-coverage      Generate an HTML coverage report under ./report

- make sync-tests         Scaffold or sync test definitions into solidity tests
- make check-tests        Checks if the solidity test files are out of sync
- make test-tree          Generates a markdown file with the test definitions
- make test-tree-prompt   Prints an LLM prompt to generate the test definitions for a given file
- make test-prompt        Prints an LLM prompt to implement the tests for a given contract

Deployment targets:

- make predeploy          Simulate a protocol deployment
- make deploy             Deploy the protocol, verify the source code and write to ./artifacts
- make resume             Retry pending deployment transactions, verify the code and write to ./artifacts

Verification:

- make verify-etherscan   Verify the last deployment on an Etherscan (compatible) explorer
- make verify-blockscout  Verify the last deployment on BlockScout
- make verify-sourcify    Verify the last deployment on Sourcify

- make refund             Refund the remaining balance left on the deployment account
```

## Testing

Using `make`:

```
$ make
[...]
Testing lifecycle:

- make test               Run unit tests, locally
- make test-fork          Run fork tests, using RPC_URL
- make test-coverage      Generate an HTML coverage report under ./report
```

Run `make test` or `make test-fork` to check the logic's accordance to the specs. The latter will require `RPC_URL` to be defined.

### Writing tests

Optionally, tests with hierarchies can be described using yaml files like [MyPlugin.t.yaml](./test/MyPlugin.t.yaml), which will be transformed into solidity files by running `make sync-tests`, thanks to [bulloak](https://github.com/alexfertel/bulloak).

Create a file with `.t.yaml` extension within the `test` folder and describe a hierarchy using the following structure:

```yaml
# MyPlugin.t.yaml

MyPluginTest:
  - given: The caller has no permission
    comment: The caller needs MANAGER_PERMISSION_ID
    and:
      - when: Calling setNumber()
        then:
          - it: Should revert
  - given: The caller has permission
    and:
      - when: Calling setNumber()
        then:
          - it: It should update the stored number
  - when: Calling number()
    then:
      - it: Should return the right value
```

Nodes like `when` and `given` can be nested without limitations.

Then use `make sync-tests` to automatically sync the described branches into solidity test files.

```sh
$ make
Testing lifecycle:
# ...

- make sync-tests         Scaffold or sync test definitions into solidity tests
- make check-tests        Checks if the solidity test files are out of sync
- make test-tree          Generates a markdown file with the test definitions

$ make sync-tests
```

Each yaml file generates (or syncs) a solidity test file with functions ready to be implemented. They also generate a human readable summary in [TESTS.md](./TESTS.md).

## Deployment 🚀

Check the available make targets to simulate and deploy the smart contracts:

```
- make predeploy        Simulate a protocol deployment
- make deploy           Deploy the protocol and verify the source code
```

### Deployment Checklist

When running a production deployment ceremony, you can use these steps as a reference:

- [ ] I have cloned the official repository on my computer and I have checked out the `main` branch
- [ ] I am using the latest official docker engine, running a Debian Linux (stable) image
  - [ ] I have run `docker run --rm -it -v .:/deployment debian:bookworm-slim`
  - [ ] I have run `apt update && apt install -y make curl git vim neovim bc`
  - On **standard EVM networks**:
    - [ ] I have run `curl -L https://foundry.paradigm.xyz | bash`
    - [ ] I have run `source /root/.bashrc`
    - [ ] I have run `foundryup`
  - On **ZkSync networks**:
    - [ ] I have run `curl -L https://raw.githubusercontent.com/matter-labs/foundry-zksync/main/install-foundry-zksync | bash`
    - [ ] I have run `source /root/.bashrc`
    - [ ] I have run `foundryup-zksync`
  - [ ] I have run `cd /deployment`
  - [ ] I have run `cp .env.example .env`
  - [ ] I have run `make init`
- [ ] I am opening an editor on the `/deployment` folder, within the Docker container
- [ ] The `.env` file contains the correct parameters for the deployment
  - [ ] I have created a new burner wallet with `cast wallet new` and copied the private key to `DEPLOYMENT_PRIVATE_KEY` within `.env`
  - [ ] I have set the correct `RPC_URL` for the network
  - [ ] I have set the correct `CHAIN_ID` for the network
  - [ ] The value of `NETWORK_NAME` is listed within `constants.mk`, at the appropriate place
  - [ ] I have set `ETHERSCAN_API_KEY` or `BLOCKSCOUT_HOST_NAME` (when relevant to the target network)
  - [ ] (TO DO: Add a step to check your own variables here)
  - [ ] I have printed the contents of `.env` to the screen
  - [ ] I am the only person of the ceremony that will operate the deployment wallet
- [ ] All the tests run clean (`make test`)
- My computer:
  - [ ] Is running in a safe location and using a trusted network
  - [ ] It exposes no services or ports
    - MacOS: `sudo lsof -iTCP -sTCP:LISTEN -nP`
    - Linux: `netstat -tulpn`
    - Windows: `netstat -nao -p tcp`
  - [ ] The wifi or wired network in use does not expose any ports to a WAN
- [ ] I have run `make predeploy` and the simulation completes with no errors
- [ ] The deployment wallet has sufficient native token for gas
  - At least, 15% more than the amount estimated during the simulation
- [ ] `make test` still runs clean
- [ ] I have run `git status` and it reports no local changes
- [ ] The current local git branch (`main`) corresponds to its counterpart on `origin`
  - [ ] I confirm that the rest of members of the ceremony pulled the last git commit on `main` and reported the same commit hash as my output for `git log -n 1`
- [ ] I have initiated the production deployment with `make deploy`

### Post deployment checklist

- [ ] The deployment process completed with no errors
- [ ] The factory contract was deployed by the deployment address
- [ ] All the project's smart contracts are correctly verified on the reference block explorer of the target network.
- [ ] The output of the latest `logs/deployment-<network>-<date>.log` file corresponds to the console output
- [ ] A file called `artifacts/deployment-<network>-<timestamp>.json` has been created, and the addresses match those logged to the screen
- [ ] I have uploaded the following files to a shared location:
  - `logs/deployment-<network>.log` (the last one)
  - `artifacts/deployment-<network>-<timestamp>.json`  (the last one)
  - `broadcast/DeployPluginRepo.s.sol/<chain-id>/run-<timestamp>.json` (the last one, or `run-latest.json`)
- [ ] The rest of members confirm that the values are correct
- [ ] I have transferred the remaining funds of the deployment wallet to the address that originally funded it
  - `make refund`

This concludes the deployment ceremony.

## Contract source verification

When running a deployment with `make deploy`, Foundry will attempt to verify the contracts on the corresponding block explorer.

If you need to verify on multiple explorers or the automatic verification did not work, you have three `make` targets available:

```
$ make
[...]
Verification:

- make verify-etherscan   Verify the last deployment on an Etherscan (compatible) explorer
- make verify-blockscout  Verify the last deployment on BlockScout
- make verify-sourcify    Verify the last deployment on Sourcify
```

These targets use the last deployment data under `broadcast/DeployPluginRepo.s.sol/<chain-id>/run-latest.json`.
- Ensure that the required variables are set within the `.env` file.
- Ensure that `NETWORK_NAME` is listed on the right section under `constants.mk`, according to the block explorer that you want to target

This flow will attempt to verify all the contracts in one go, but yo umay still need to issue additional manual verifications, depending on the circumstances.

### Routescan verification (manual)

```sh
$ forge verify-contract <address> <path/to/file.sol>:<contract-name> --verifier-url 'https://api.routescan.io/v2/network/<testnet|mainnet>/evm/<chain-id>/etherscan' --etherscan-api-key "verifyContract" --num-of-optimizations 200 --compiler-version 0.8.28 --constructor-args <args>
```

Where:
- `<address>` is the address of the contract to verify
- `<path/to/file.sol>:<contract-name>` is the path of the source file along with the contract name
- `<testnet|mainnet>` the type of network
- `<chain-id>` the ID of the chain
- `<args>` the constructor arguments
  - Get them with `$(cast abi-encode "constructor(address param1, uint256 param2,...)" param1 param2 ...)`

## Security 🔒

If you believe you've found a security issue, we encourage you to notify us. We welcome working with you to resolve the issue promptly.

Security Contact Email: sirt@aragon.org

Please do not use the public issue tracker to report security issues.

## Contributing 🤝

Contributions are welcome! Please read our contributing guidelines to get started.

## License 📄

This project is licensed under AGPL-3.0-or-later.

## Support 💬

For support, join our Discord server or open an issue in the repository.
