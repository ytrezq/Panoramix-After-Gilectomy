// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {DefillamaCreditAccountData, DefillamaPoolData} from "../types/Defillama.sol";

/// @title  Compressor contract for Defillama
interface IDefillamaCompressor is IVersion {
    /// @notice Returns data for pools in given configurators
    function getPools(address[] memory configurators) external view returns (DefillamaPoolData[] memory pools);

    /// @notice Returns data for pools in all configurators found in market configurator factory
    function getPools() external view returns (DefillamaPoolData[] memory pools);

    /// @notice Returns credit managers in given configurators
    function getCreditManagers(address[] memory configurators)
        external
        view
        returns (address[] memory creditManagers);

    /// @notice Returns credit managers in all configurators found in market configurator factory
    function getCreditManagers() external view returns (address[] memory creditManagers);

    /// @notice Returns data for credit accounts in a given `creditManager`
    function getCreditAccounts(address creditManager)
        external
        view
        returns (DefillamaCreditAccountData[] memory data);

    /// @dev Same as above but with offset and limit
    function getCreditAccounts(address creditManager, uint256 offset, uint256 limit)
        external
        view
        returns (DefillamaCreditAccountData[] memory data);
}
