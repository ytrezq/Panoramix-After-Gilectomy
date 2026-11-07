# SubProxy Methods

Stateless methods to be `delegatecall`ed from a Sky [`SubProxy`](https://github.com/sky-ecosystem/endgame-toolkit/blob/a98f53d/src/SubProxy.sol), enabling a `SubProxy` to perform simple operations **without crafting a bespoke Prime spell**.

## Supported methods

- **ERC20 transfer** — move an ERC20 token from the `SubProxy`'s balance to a recipient.

## Development

```shell
forge build      # compile (solc 0.8.16, optimizer off, evm cancun)
forge test       # run tests against ethereum mainnet fork, requires `ETH_RPC_URL` to be set
forge fmt        # format
```

Clone with submodule (`forge-std`):

```shell
git clone --recurse-submodules <repo-url>
# or, after a plain clone:
git submodule update --init --recursive
```

## Deployment

The contract has **no constructor arguments**, so no deploy script is needed.

1. Set ENV variables
    - ETH_RPC_URL: ethereum mainnet rpc url
    - ETHERSCAN_API_KEY: etherscan api key to verify the contract
2. Run command to deploy
    ```shell
    forge create src/SubProxyMethods.sol:SubProxyMethods \
        --rpc-url "$ETH_RPC_URL" \
        --account <ACCOUNT_NAME> \
        --verify \
        --broadcast
    ```
