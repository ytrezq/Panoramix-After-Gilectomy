# maple

- Scope: 43 smart-contract assets, Ethereum addresses: MapleGlobals, PoolManager / Pool / PoolDelegateCover,
  PoolDeployer, PoolPermissionManager, withdrawal managers (cyclical and queue), open-term loans, loan managers and
  refinancer, strategies (Aave, Sky, Basic) with factories / implementations / initializers, SyrupRouter,
  BorrowerActions and GovernorTimelock. Some are marked "for reference" on the page.
- No in-scope repository link (the page links maple-labs/maple-v2-audits). Copied: maple-labs/maple-core-v2 @ main
  (default branch), Maple's integration repository, which pins every protocol module as a submodule: pool, globals,
  fixed-term-loan(-manager), open-term-loan(-manager), withdrawal-manager-cyclical / -queue, pool-permission-manager,
  strategies (maple-strategies: Aave / Sky / Basic), syrup-utils (SyrupRouter, MapleBorrowerActions), liquidations,
  erc20, erc20-helper, address-registry; all submodules cloned at their pinned commits (BUSL-1.1).
- Not obviously covered: GovernorTimelock (Maple's own timelock; maple-labs/governor-timelock is not public,
  the copies only hold OpenZeppelin's GovernorTimelock* governance extensions).
- Left out: maple-labs/maple-v2-audits (audit reports).
