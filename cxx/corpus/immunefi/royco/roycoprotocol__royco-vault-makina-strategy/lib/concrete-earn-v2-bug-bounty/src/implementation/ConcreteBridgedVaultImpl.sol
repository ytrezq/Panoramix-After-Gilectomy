// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ConcreteAsyncVaultImpl} from "./ConcreteAsyncVaultImpl.sol";
import {IConcreteBridgedAsyncVaultImpl} from "../interface/IConcreteBridgedAsyncVaultImpl.sol";
import {ConcreteV2RolesLib as RolesLib} from "../lib/Roles.sol";

/**
 * @title ConcreteBridgedAsyncVaultImpl
 * @notice A vault implementation that extends ConcreteAsyncVaultImpl with unbacked minting capabilities.
 * @notice This vault type is intended for cross chain migrations of vaults such as during a predeposit phase.
 *      It allows for the initial minting of shares without depositing any underlying assets.
 *      Once the predeposit phase is complete, the vault can be migrated to a standard vault.
 *      The vault is designed to be used in conjunction with the ConcretePredepositVaultImpl.
 *      Underlying assets are directly allocated to an underlying strategy contract without minting shares.
 *      This results in an exchange rate between the shares and the underlying assets that is equal to the predeposit vault.
 */
contract ConcreteBridgedAsyncVaultImpl is ConcreteAsyncVaultImpl, IConcreteBridgedAsyncVaultImpl {
    /**
     * @dev Constructor
     * @param factory The address of the factory
     */
    constructor(address factory) ConcreteAsyncVaultImpl(factory) {}

    /**
     * @notice Mints vault shares without depositing any underlying assets.
     * @dev Strictly `VAULT_MANAGER`.  No assets are transferred in – used only for vault migration.
     *      assets backing newly minted shares are expected to be allocated directly on strategy level.
     *      Shares are minted for later distribution to end users.
     * @param shares - Amount of shares to mint for the owner.
     */
    function unbackedMint(uint256 shares) external onlyRole(RolesLib.VAULT_MANAGER) {
        require(shares != 0, ZeroAmount());
        require(totalSupply() == 0, NotInitialMint());
        _mint(msg.sender, shares);
        emit UnbackedMint(shares);
    }
}

