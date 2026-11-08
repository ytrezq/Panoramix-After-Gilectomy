# Serai: not an EVM-contract program

- Scope: 11 Blockchain/DLT assets, all Rust crates of serai-dex/serai at `develop`: crypto/ciphersuite, dkg, dkg/musig, frost
  (modular-frost), schnorrkel, schnorr, dalek-ff-group, transcript, multiexp, and networks/bitcoin; plus primacy of impact.
- No smart contract asset, no contract address.
- The repository does hold Solidity (networks/ethereum/contracts: Router.sol, Schnorr.sol, Deployer.sol, Sandbox.sol, checked
  at develop 4b89cf02), but the Ethereum integration is not in the program's scope: nothing copied.
