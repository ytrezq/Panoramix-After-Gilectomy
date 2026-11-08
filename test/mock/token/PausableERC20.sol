// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./MockERC20.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract PausableERC20 is PausableUpgradeable, MockERC20 {
    function transfer(address recipient, uint256 amount) public override whenNotPaused returns (bool) {
        return super.transfer(recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    )
        public
        override
        whenNotPaused
        returns (bool)
    {
        return super.transferFrom(sender, recipient, amount);
    }

    function pause() external {
        _pause();
    }

    function unpause() external {
        _unpause();
    }
}
