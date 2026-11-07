# sei

- Scope: 4 Blockchain/DLT assets: sei-protocol/sei-chain ("Sei Chain"), sei-protocol/go-ethereum, sei-protocol/sei-js,
  and Primacy of Impact. Sei is a Cosmos-SDK chain with a built-in EVM; no smart-contract asset, no explorer address.
- Copied: sei-protocol/sei-chain @ main (no ref in the link: default branch), for its EVM sources only (92 own .sol):
  the precompile interfaces (precompiles/*: bank, staking, distribution, gov, wasmd, json, addr, pointerview, p256...;
  giga/evmonly/precompiles), and the EVM test and example contracts (contracts/src: EVM compatibility, selfdestruct,
  transient storage, SSTORE gas testers...; example/contracts; evmrpc; integration_test, including a Uniswap V2 copy).
- On main the CW<->ERC pointer contracts are no longer in the tree (none found).
- Left out: sei-protocol/go-ethereum (the EVM node fork: node software) and sei-js (TypeScript SDK).
- The other link on the page, oak-security/audit-reports, holds audit PDFs.
