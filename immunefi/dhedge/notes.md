# dHEDGE

- Scope: "PoolFactory and linked contracts" on Polygon, Optimism, Ethereum, Base, Arbitrum and HyperEVM (one PoolFactory
  address each), plus primacy of impact.
- Copied dhedge/V2-Public (linked from the page) at its default branch master (ec35e7e8; license file read as AGPL-3.0,
  ISC in package.json): 841 .sol (PoolFactory, PoolLogic, PoolManagerLogic, guards, asset guards, price aggregators...) with 18
  submodules and its npm imports.
- The "linked contracts" (guards, oracles per chain) are assumed to be in this repository; deployed versions not checked.
- Left out: santipu03/santipu03 and zobront/audits (audit reports linked from the page).
