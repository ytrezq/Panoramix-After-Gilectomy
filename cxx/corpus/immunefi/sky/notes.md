# Sky (sky)

- Scope: 251 smart-contract assets, all GitHub links into 53 repositories (sky-ecosystem/*, ex-makerdao, plus dapphub/ds-weth): MCD core (dss), oracles (median, osm, LP oracles), joins, PSMs, flappers, bridges (Optimism, Arbitrum, StarkNet L1 side, LayerZero), allocator, lockstake, USDS/SKY/sUSDS/stUSDS, emergency spells, the diamond PAU and its facets, PAS. Also 4 websites (not copied). No explorer address in the scope (chainlog.sky.money lists the deployments).
- Each repository copied at the ref its scope links name (master/main/dev mostly; dss-gem-joins v1.2, vote-delegate v3, sdai susds, pas 947e71c); stusds is linked at its root: default branch.
- Repositories linked at several refs (one copy each, so one ref):
  - dss: master (10 links); join.sol (linked at v1.2) and abaci.sol (linked at c8d4c806) differ on master.
  - dss-flappers: master holds every linked file (master/dev/beam links) except FlapperMom.sol, which no branch holds any more.
  - sky: one-direction (MkrSky.sol as linked; Sky.sol is the same blob as on dev).
  - lockstake: master (adds LockstakeCappedOsmWrapper.sol, linked at master); LockstakeClipper.sol differs from the v2 branch the other links name.
- sky-ecosystem/mip21-toolkit (RwaLiquidationOracle link) no longer exists: it was renamed rwa-toolkit (makerdao/mip21-toolkit resolves to rwa-toolkit's commit), so it is covered by the rwa-toolkit copy.
- sky-ecosystem/sky-oapp-oft has no license file: only its sources with open SPDX headers are copied (the in-scope GovernanceOAppSender.sol and SkyOFTAdapter.sol among them); 17 UNLICENSED ones are skipped (manifest skipped_unlicensed). Its Solana programs (Rust) are not EVM. sp-beam's 3 sources without a header are skipped the same way.
- Not EVM, not copied: the Cairo L2 contracts of starknet-dai-bridge (its L1 .sol are copied).
- Out-of-scope links not taken: mcd-security (docs), Synthetixio/synthetix (origin of StakingRewards, copied in endgame-toolkit), dai.js, gov-polling-db, governance-portal-v2 (frontends/off-chain).
- Size: diamond-pau brings 173 nested submodules (about 79 MB of sources), the bulk of this program.
