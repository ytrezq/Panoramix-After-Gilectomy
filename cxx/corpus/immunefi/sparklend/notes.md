# Spark (sparklend)

- Scope: 385 assets: ~315 contract addresses (Ethereum, Gnosis, Base, Arbitrum, Optimism, Unichain, Avalanche, World Chain)
  named as in sparkdotfi/spark-address-registry, 23 GitHub file links, and docs/app repositories.
- In-scope GitHub links (marsfoundation, now sparkdotfi), at the branch each link names: xchain-ssr-oracle@master,
  spark-alm-controller@master, aave-v3-core@master (renamed sparklend-v1-core), sparklend@master (renamed sparklend-deployments;
  its submodules pin sparklend-v1-core, aave/aave-v3-periphery and aave-helpers), spark-gov-relay@master, spark-psm@master,
  sparkdotfi/spark-vaults-v2@dev.
- Address-only contracts, matched by name to sparkdotfi repositories (default branches, 2026-11-07): spark-rewards (*_REWARDS),
  sparklend-advanced (ratio oracles, rate strategies), sparklend-kill-switch, sparklend-cap-automator, sparklend-freezer
  (FREEZER_MOM, SPELL_*), spark-savings-intents, spark-user-actions (USER_ACTIONS_PSM_VARIANT1), spark-vaults (sUSDC, vault v1),
  spark-pau-deploy (PAU core and *_FACET via its pinned submodules sky-ecosystem/diamond-pau, pau-administered-agent, sky-pau-registry).
- Already present as submodules, not copied again: xchain-helpers (SPARK_RECEIVER, DSR/SSR receivers), aave-v3-periphery and
  aave-helpers (UI/WETH gateway/incentives/treasury, CONFIG_ENGINE, TRANSPARENT_PROXY_FACTORY).
- Licenses: AGPL-3.0 everywhere, BUSL-1.1 for sparklend-v1-core: all 16 copied.
- Left out: spark-app (frontend), spark-docs, spark-dev-docs (docs; spark-dev-docs is no longer public).
- Not covered: SPK and stSPK (no public repository found), SPARK_PROXY (Sky's SubProxy, sky-ecosystem). The scope's
  spark-alm-controller link names master; its newer dev branch (ALM_CONTROLLER_v1.11.0 era) was not taken.
- Size: 363 MB on disk, mostly recursive submodules repeated across repos (spark-pau-deploy alone has 177).
