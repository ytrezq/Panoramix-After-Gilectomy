// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626Mock} from "./ERC4626Mock.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";

contract ConcreteERC4626Mock is ERC4626Mock {
    constructor(address underlying) ERC4626Mock(underlying) {}

    function simulateLossInVault(address burner, uint256 lossAmount) external {
        IERC20(asset()).transfer(burner, lossAmount);
    }
}
