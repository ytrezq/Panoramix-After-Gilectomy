// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.22;

import { DataTypes } from "../../lib/aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";

interface IPoolAddressesProviderLike {

    function getPool() external view returns (address);

    function getPoolConfigurator() external view returns (address);

}

interface IPoolLike {

    function getReserveData(address asset) external view returns (DataTypes.ReserveData memory);

}

interface IPoolConfiguratorLike {

    function setBorrowCap(address asset, uint256 newBorrowCap) external;

    function setSupplyCap(address asset, uint256 newSupplyCap) external;

}

interface IScaledBalanceTokenLike {

    function scaledTotalSupply() external view returns (uint256);

}
