# Lista V3

A Uniswap V3 fork renamed to Lista V3, with the NFT position manager deployed behind an upgradeable proxy. Factory, pool, and router behavior tracks upstream Uniswap V3.

## Contracts

### Core (`src/core/`)

- `ListaV3Factory` — canonical factory. Plain (non-upgradeable) deploy; constructor sets the deployer as owner and seeds the 500 / 3000 / 10000 fee tiers. Keeps `NoDelegateCall` as upstream.
- `ListaV3Pool` — AMM pool, CREATE2-deployed by the factory, not upgradeable.
- `ListaV3PoolDeployer` — base of the factory; writes transient parameters so the pool constructor can read them back, keeping `POOL_INIT_CODE_HASH` constant for off-chain address derivation.

### Periphery (`src/periphery/`)

- `NonfungiblePositionManager` — wraps positions as ERC-721 NFTs. **Hybrid upgradeable**: the ERC-721 / permit stack uses `ERC721PermitUpgradeable` (storage-backed, behind a `TransparentUpgradeableProxy`), while `factory` and `WETH9` remain constructor-set `immutable`s in the implementation bytecode. Every impl upgrade must re-pass the original `(factory, WETH9)` to the new impl's constructor.
- `SwapRouter`, `V3Migrator`, `Quoter`, `QuoterV2`, `NonfungibleTokenPositionDescriptor`, `PairFlash` — deployed normally (non-upgradeable).

## Deployment outline

1. Deploy `ListaV3Factory` directly. The deployer becomes owner; call `setOwner` afterwards if a different owner is required.
2. Deploy a `ProxyAdmin` for the NPM proxy (and any future upgradeable contracts).
3. Deploy `NonfungiblePositionManager` impl with `(factory, WETH9)`.
4. Deploy `TransparentUpgradeableProxy(npmImpl, proxyAdmin, abi.encodeWithSelector(NonfungiblePositionManager.initialize.selector, tokenDescriptor))`.
5. Deploy `SwapRouter`, `V3Migrator`, etc. against the factory address.

Operational notes:

- The NPM implementation should have its initializer consumed post-deploy (e.g. `npmImpl.initialize(0xdead)`) to close the Parity-style impl-takeover window.
- Every NPM impl upgrade must re-pass the same `(factory, WETH9)` to the new impl's constructor — the values are baked into impl bytecode as immutables. A deploy script that reads `npm.factory()` / `npm.WETH9()` from the existing proxy and forwards them to the new impl's constructor is the safest pattern.
- Pool addresses are derived from the factory via `PoolAddress.computeAddress`. If `ListaV3Pool` bytecode is ever changed, `PoolAddress.POOL_INIT_CODE_HASH` must be recomputed — the value in `src/periphery/libraries/PoolAddress.sol` is only valid for the currently-checked-in pool source and build settings.
- Re-verify `POOL_INIT_CODE_HASH` before deploying to a new chain. The value is machine-deterministic given `bytecode_hash = "none"` in `foundry.toml`, but a different toolchain version, optimizer setting, or solc patch can still shift it. Run `testInitCodeHash` in `test/periphery/FullFlowTest.t.sol` against your build environment as a pre-deploy gate; if it fails, update the constant before deploying or off-chain pool address derivation will silently point at the wrong addresses.

## Build & test

Uses Foundry with Solidity 0.7.6.

```sh
forge build
forge test
```

The end-to-end flow (pool creation, mint, swap, increase / decrease liquidity, collect, transfer, burn) runs in `test/periphery/FullFlowTest.t.sol`, which also exercises the proxy wiring and asserts NPM initializer state / ERC-165 registrations.

## License

Source is GPL-2.0-or-later (see `NOTICE` for derivation and attribution).

## Dependencies

Git submodules under `lib/`:

- `forge-std`
- `openzeppelin-contracts` at `v3.4.2-solc-0.7` — non-upgradeable contracts and proxy wrappers (`TransparentUpgradeableProxy`, `ProxyAdmin`).
- `openzeppelin-contracts-upgradeable` at `v3.4.2-solc-0.7` — upgradeable ERC-721, Initializable, Context, ERC-165.
- `solidity-lib` — Uniswap math helpers.
