## Foundry + Makefile

This project uses [Foundry](https://book.getfoundry.sh/) under the hood, wrapped in a convenient **Makefile** to streamline common tasks such as building, testing, deploying, etc.

### Prerequisites

-   [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
---

## Quick Start

1. **Clone** the repository and navigate into it.
2. **Install** dependencies:
   ```shell
   make install
   ```
3. **Build** the project:
   ```shell
   make build
   ```
4. **Test** the project:
   ```shell
   make test
   ```

---

## Available Make Targets

Below are the main targets from the [`Makefile`](./Makefile) and what they do.

| Target                         | Description                                                                        |
|--------------------------------|------------------------------------------------------------------------------------|
| `make help`                    | Shows help information and usage examples                                          |
| `make all`                     | Removes artifacts, reinstall dependencies, updates, then builds                    |
| `make clean`                   | Cleans Foundry artifacts (removes generated files under `out/` and `cache/`)       |
| `make remove`                  | Removes modules (`.gitmodules` and `lib`)                                          |
| `make install`                 | Installs dependencies (OpenZeppelin, forge-std, etc.)                              |
| `make build`                   | Compiles all contracts using Foundry                                               |
| `make test`                    | Runs all Foundry tests                                                              |
| `make anvil`                   | Starts a local Anvil testnet on a deterministic mnemonic                           |
| `make deploy-capyfi-protocol`  | Example deployment (see `script/DeployCapyfiProtocolAll.s.sol`)                    |

> **Note**: Some deployment targets require environment variables (RPC URLs, private keys, etc.). See [`.env`](./.env) for configuration and usage.

---

## Deployment Usage

You can pass extra arguments to the `make` deployment targets through `ARGS`. For example, to deploy the **Interest Rate Models** to `latestnet`:

```shell
make deploy-irm ARGS="--network latestnet"
```

The Makefile detects `--network latestnet` and sets up the correct RPC URL and private key from your `.env` file.

---

## Local Development

To test locally:
1. In one terminal, run:
   ```shell
   make anvil
   ```
   This starts a local development chain at [http://localhost:8545](http://localhost:8545).

2. In another terminal, deploy contracts or run tests:
   ```shell
   make build
   make test
   ```
   or
   ```shell
   make deploy-capyfi-protocol
   ```
   (which defaults to using the local chain if no `ARGS` are passed).

---

## Whitelist Functionality

This fork adds whitelist functionality to the Compound protocol, allowing for controlled access to token minting operations. The whitelist implementation:

- Uses role-based access control with DEFAULT_ADMIN_ROLE and WHITELISTED_ROLE
- Follows the UUPS upgradeability pattern
- Integrates with CToken contracts to restrict minting operations
- Can be activated/deactivated by admins

For details on the whitelist implementation and security considerations, see the [audit documentation](./docs/audit-docs.md).

---

## Further Documentation

-   [Audit Documentation](./docs/audit-docs.md) - Detailed overview of modifications and whitelist functionality
-   [Foundry Book](https://book.getfoundry.sh/) - official documentation
-   [Solidity](https://docs.soliditylang.org/) - reference docs for the Solidity language
-   [OpenZeppelin](https://docs.openzeppelin.com/contracts) - for audited base contracts

For any custom logic or advanced usage (like verifying on specific explorers, advanced arguments, etc.), see the [Makefile](./Makefile) or the [`scripts/`](./script) folder for reference.