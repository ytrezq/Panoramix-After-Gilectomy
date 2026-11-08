// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./MockERC20.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract ApprovalPauseERC20 is PausableUpgradeable, MockERC20 {
    function approve(address spender, uint256 amount) public override whenNotPaused returns (bool) {
        return super.approve(spender, amount);
    }

    function pause() external {
        _pause();
    }

    function unpause() external {
        _unpause();
    }
}
