# rhinofi

- Scope: 9 smart-contract assets, explorer addresses of rhino.fi's bridge deposit contracts on Arbitrum, BSC, Optimism,
  Polygon, Polygon zkEVM and zkSync Era, and of its multisigs on Arbitrum, BSC and Polygon.
- No in-scope repository link. Copied: rhinofi/contracts_public @ master (default branch), linked from the page:
  bridge-deposit/ (DVFDepositContract and its Blast / Ape variants, BridgeVM): the bridge contracts of the scope.
- Left out: starkware-libs/starkex-contracts (linked for StarkEx audits: rhino.fi's former StarkEx deployment, no
  in-scope address) and the multisigs (Gnosis Safe deployments, third-party code).
- The zkSync Era bridge is the same Solidity source compiled with zksolc (EraVM bytecode, not EVM).
