// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract MockStakedUSDS is ERC4626 {

    constructor(IERC20 asset_) ERC20("MockSUSDS", "msUSDS") ERC4626(asset_) {

    }

    uint256 public ssr = 0;

    function setSsr(uint256 ssr_) external {
        ssr = ssr_;
    }
}
