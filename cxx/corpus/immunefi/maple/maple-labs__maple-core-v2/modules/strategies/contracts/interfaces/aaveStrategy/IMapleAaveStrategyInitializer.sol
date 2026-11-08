// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IMapleAaveStrategyInitializer {

    /**
     *  @dev   Emitted when the proxy contract is initialized.
     *  @param aavePool    Address of the Aave pool.
     *  @param aaveToken   Address of the Aave token.
     *  @param pool        Address of the Maple pool.
     *  @param fundsAsset  Address of the underlying asset.
     *  @param poolManager Address of the Maple pool manager.
     */
    event Initialized(
        address indexed aavePool,
        address indexed aaveToken,
        address indexed pool,
        address fundsAsset,
        address poolManager
    );

}
