// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC4626} from "./MockERC4626.sol";
import {IMetaVault} from "../tranches/interfaces/IMetaVault.sol";

contract MockMetaERC4626 is MockERC4626, IMetaVault {

    constructor(IERC20 token) MockERC4626(token) {}

    function deposit(address, uint256 tokenAssets, address receiver) external returns (uint256) {
        return deposit(tokenAssets, receiver);
    }
    function mint(address, uint256 shares, address receiver) external returns (uint256) {
        return mint(shares, receiver);
    }
    function withdraw(address, uint256 tokenAssets, address receiver, address owner) external returns (uint256) {
        return withdraw(tokenAssets, receiver, owner);
    }
    function redeem(address, uint256 shares, address receiver, address owner) external returns (uint256) {
        return withdraw(shares, receiver, owner);
    }
}
