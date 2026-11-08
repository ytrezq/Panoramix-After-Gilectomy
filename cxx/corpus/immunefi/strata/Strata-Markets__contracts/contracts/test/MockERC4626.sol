// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockERC4626 is ERC4626 {

    bool public enabled = true;

    constructor(IERC20 token) ERC20("MockERC4626", "M4626") ERC4626(token)  {}

    function setEnabled(bool _enabled) public {
        enabled = _enabled;
    }

    function maxDeposit(address receiver) public view override returns (uint256) {
        if (!enabled) {
            return 0;
        }
        return super.maxDeposit(receiver);
    }
    function maxMint(address receiver) public view override returns (uint256) {
        if (!enabled) {
            return 0;
        }
        return super.maxMint(receiver);
    }
    function maxRedeem(address owner) public view override returns (uint256) {
        if (!enabled) {
            return 0;
        }
        return super.maxRedeem(owner);
    }
    function maxWithdraw(address owner) public view override returns (uint256) {
        if (!enabled) {
            return 0;
        }
        return super.maxWithdraw(owner);
    }
}
