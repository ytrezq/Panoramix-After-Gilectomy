// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @notice Test helper contract for testing execute functionality
 * @dev Used to verify that Locker can execute arbitrary calls
 */
contract MockTarget {
    uint256 public value;
    bool public shouldRevert;

    function setValue(uint256 _value) external {
        if (shouldRevert) revert("Mock revert");
        value = _value;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    receive() external payable {}
}
