// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface ISyrupRateProvider {

    /**
     * @return The value of Pool Token in terms of the underlying
     */
    function getRate() external view returns (uint256);

    /**
     *  @dev    The address of the ERC4626 Vault.
     *  @return pool The address of the ERC4626 Vault.
     */
    function pool() external view returns (address pool);

}

