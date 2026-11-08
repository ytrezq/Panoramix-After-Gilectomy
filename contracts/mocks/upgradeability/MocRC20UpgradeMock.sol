// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

// This contract is not intended to be used in a production system
// It was designed to be used in a testing environment only

import { MocRC20, ERC20Upgradeable } from "../../tokens/MocRC20.sol";
import { IERC20Upgradeable } from "../../interfaces/IMocRC20.sol";

/**
 * @title MocRC20Mock
 * @dev Only for upgradeability testing purposes.
 */
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract MocRC20Mock is MocRC20 {
    uint256 public newVariable;

    function initializeMock() external {
        newVariable = 42;
    }

    function totalSupply() public view override(ERC20Upgradeable, IERC20Upgradeable) returns (uint256) {
        return 1 + newVariable + super.totalSupply();
    }
}
