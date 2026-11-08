// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.22;

import { DataTypes } from "../../lib/aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";

interface IACLManagerLike {

    function addRiskAdmin(address admin) external;

}

interface IPoolLike {

    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;

    function flashLoanSimple(address receiver, address asset, uint256 amount, bytes calldata params, uint16 referralCode) external;

    function repay(address asset, uint256 amount, uint256 interestRateMode, address onBehalfOf) external returns (uint256);

    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    function withdraw(address asset, uint256 amount, address to) external returns (uint256);

    function getBorrowCap(address asset) external view returns (uint256);

    function getReservesList() external view returns (address[] memory);

    function getReserveData(address asset) external view returns (DataTypes.ReserveData memory);

}

interface IScaledBalanceTokenLike {

    function scaledTotalSupply() external view returns (uint256);

}
