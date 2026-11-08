# deBridge

- Scope: 90 EVM addresses on Ethereum, BNB Chain, Polygon, HECO, Arbitrum, Avalanche and Fantom: ProxyAdmin, deBridgeGate,
  DeBridgeToken, DeBridgeTokenDeployer, SignatureVerifier, CallProxy, SimpleFeeProxy (proxies and implementations), WethGate.
- All these names are deBridge v1 contracts of debridge-finance/debridge-contracts-v1 (linked from the page): copied at its
  default branch main (2e9f9c73, BUSL-1.1; 47 .sol with the @openzeppelin/contracts(-upgradeable) npm imports).
- The ProxyAdmin/proxies are OpenZeppelin's (in node_modules). Deployed versions per chain were not checked against the
  explorers.
