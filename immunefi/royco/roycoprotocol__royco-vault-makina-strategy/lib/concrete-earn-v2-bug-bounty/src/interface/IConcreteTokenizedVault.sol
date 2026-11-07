// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC4626} from "@openzeppelin-contracts/interfaces/IERC4626.sol";

interface IConcreteTokenizedVault is IERC4626 {
    function totalAssetsAt(uint32 timestamp) external view returns (uint256);

    function cachedTotalAssets() external view returns (uint256);

    function totalSupplyAt(uint32 timestamp) external view returns (uint256);

    function balanceOfAt(address account, uint32 timestamp) external view returns (uint256);
}
