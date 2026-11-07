// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IMetaVault is IERC4626 {

    function deposit(address token, uint256 tokenAssets, address receiver) external returns (uint256);
    function mint(address token, uint256 shares, address receiver) external returns (uint256);
    function withdraw(address token, uint256 tokenAssets, address receiver, address owner) external returns (uint256);
    function redeem(address token, uint256 shares, address receiver, address owner) external returns (uint256);

}
