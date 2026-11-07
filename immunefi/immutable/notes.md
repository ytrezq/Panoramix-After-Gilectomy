# Immutable

- Scope: the Immutable zkEVM token bridge: on Ethereum the Bridge and the
  Axelar Adapter (proxies and implementations);
  on Immutable zkEVM (chain 13371) the child Bridge, Adapter and the
  ChildERC20 token template.
- Copied: immutable/zkevm-bridge-contracts at its default branch (main; no
  deployment tag), Apache-2.0, with its submodules: RootERC20Bridge(FlowRate),
  RootAxelarBridgeAdaptor, ChildERC20Bridge, ChildAxelarBridgeAdaptor and
  ChildERC20 are there.
- Left out: immutable/contracts (presets; linked for its audits, no address in
  scope).
