# StarGuard module

A module for the Sky Protocol that enables permissionless execution of Star Spells in a separate transaction after they were "whitelisted" by the core spell.

## Overview

The StarGuard module resolves multiple problems with direct inclusion of the Star spells into the Core spell, the main of which is the bottleneck caused by the size of the core spell "cast" transaction (limited by the max block size). This module fixes this problem by allowing permissionless execution of a Star spell after it has been "whitelisted" by the core spell.

In other words, it replaces current flow:

```
1st transaction: Anyone ──► Core Spell ─┬─► SubProxy A ──► Star Spell A1
                                        └─► SubProxy B ──► Star Spell B1
```

with the updated flow:

```
1st transaction: Anyone ──► Core Spell ─┬─► StarGuard A.plot(Star Spell A1)
                                        └─► StarGuard B.plot(Star Spell B1)
2nd transaction: Anyone ──────────────────► StarGuard A.exec() ──► SubProxy A ──► Star Spell A1
3rd transaction: Anyone ──────────────────► StarGuard B.exec() ──► SubProxy B ──► Star Spell B1
```

## Trust assumptions

- The governance (any address in `wards`) is considered to be fully trusted. `StarGuard.wards` is expected to only contain `MCD_PAUSE_PROXY`
- The `SubProxy` is expected to work correctly. `SubProxy.wards` is expected to contain `StarGuard`
- The Star spells are fully trusted, expected to be validated accordingly
    - Additional sanity checks are implemented as a precaution:
        - `codehash` enforcement at the time of the execution
        - `exec()` reentrancy protection
        - `SubProxy.wards` check after payload execution to still contain `StarGuard` (note: it's not technically possible to guarantee that another address was added there which can modify `wards` in the following transaction)
    - Expected to implement the required functions (i.e., `execute()` and `isExecutable()`)
- Any other address: Untrusted

## Features

- Codehash validation of the payload at the time of the execution
- Configurable maximum delay – a deadline, after which the Star payload is no longer executable
- Validation that Star spell did not remove StarGuard from the authorized contracts

## Payload requirements

Each payload contract is required to provide certain external interfaces:

```solidity
interface StarSpellLike {
    /**
     * @notice Executes actions performed on behalf of the `SubProxy` – i.e. the actual payload
     * @dev Required, will be called by the StarGuard during permissionless execution
     */
    function execute() external;
    /**
     * @notice Checks if the star payload is executable in the current block
     * @dev Required, useful for implementing "earliest launch date" or "office hours" strategy
     * @return result The result of the check (true = executable, false = not)
     */
    function isExecutable() external view returns (bool result);
}
```

### Environment variables
- `MAINNET_RPC_URL` (required for testing) – the RPC url to the Ethereum Mainnet node
- `ETHERSCAN_API_KEY` (required for deployment) – the API key from [Etherscan](https://etherscan.io)

## Testing and linting

#### Testing

- Provide required env variable outlined above
- Execute `make test`

#### Linting and formatting
- To format solidity code, execute `make format`
- To verify [solidity natspec](https://docs.soliditylang.org/en/latest/natspec-format.html), use `make lint-spec`

### Deployment

To deploy the contract, you can use `Deploy.s.sol` script by providing `subProxy` address as a parameter. Here are the example commands:

```sh
# To estimate gas for the script
forge script script/Deploy.s.sol:Deploy --rpc-url mainnet --sender $(cast wallet address --account $ACCOUNT) --account $ACCOUNT --sig "run(address)" $SUBPROXY_ADDRESS 
# To broadcast and verify contract on etherscan
forge script script/Deploy.s.sol:Deploy --rpc-url mainnet --sender $(cast wallet address --account $ACCOUNT) --account $ACCOUNT --sig "run(address)" $SUBPROXY_ADDRESS --broadcast --verify
```

## Audits

Audit reports are available in the [`audits/`](./audits/) directory. The module has been audited by:

- [Cantina](https://cantina.xyz/portfolio/af6da668-1831-43da-8bcd-0ae987238e12)
- [ChainSecurity](https://www.chainsecurity.com/security-audit/sky-star-guard)
