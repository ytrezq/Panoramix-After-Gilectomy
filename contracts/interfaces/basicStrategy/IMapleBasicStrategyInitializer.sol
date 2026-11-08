// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IMapleBasicStrategyInitializer {

    /**
     *  @dev   Emitted when the proxy contract is initialized.
     *  @param pool          Address of the pool contract.
     *  @param poolManager   Address of the pool manager contract.
     *  @param strategyVault Address of the ERC4626 compliant Vault.
     */
    event Initialized(address indexed pool, address indexed poolManager, address indexed strategyVault);

}
