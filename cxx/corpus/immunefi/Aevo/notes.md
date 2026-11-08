# Aevo (Aevo)

- Scope: two deposit contracts. No repository is linked on the page.
- Ethereum (0x4082C964...): an L1ChugSplashProxy whose implementation is OP Stack's L1StandardBridge (etherscan's verified sources: contracts-bedrock src/L1/L1StandardBridge.sol, solc 0.8.15). Its source is ethereum-optimism/optimism (contracts-bedrock), which the optimism program copies; not copied again here.
- Arbitrum (0x80d40e32...): a Socket "Vault" (Sourcify: src/Vault.sol with Gauge.sol and ConnectorPlug.sol, solc 0.8.13).
- Copied: SocketDotTech/socket-plugs (then named app-chain-token) at ac25cce (2023-08-08), the commit whose src/Vault.sol and src/ConnectorPlug.sol are closest to the verified ones (4 and 2 lines of difference; Gauge.sol identical). No commit matches them exactly.
