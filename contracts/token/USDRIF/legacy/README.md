# USDRIF Legacy Code

The USDRIF token, also known as StableTokenV2, was deployed and migrated from StableTokenV1 prior to the launch of the ROC V2 protocol. This token leverages the AccessControl library from OpenZeppelin to accommodate multiple minter and burner roles. However, only the admin, in this case, the MocCore contract, has the authority to grant or revoke these roles.

For deployment details, please refer to the following [link](https://github.com/money-on-chain/RDOC-Contract/tree/v0.1.16.2).

In the implementation of the multi-collateral system, it's necessary for USDRIF to be minted and burned by other buckets. To facilitate this, we are currently upgrading the token to allow for role assignment and revocation by governance.

The legacy contracts' code remains included solely for testing and verifying the upgrade process. It will be removed in a subsequent commit.

TODO: after the upgrade remove:
- Legacy contracts folder
- dependencies:
    - "moc-main-v1.0.6": "github:money-on-chain/main-sc-protocol-v2#v1.0.6-rc",
    - "@openzeppelin-v4.8.0/contracts": "npm:@openzeppelin/contracts@^4.8.0",
    - "@openzeppelin-v4.8.0/contracts-upgradeable": "npm:@openzeppelin/contracts-upgradeable@^4.8.0",


