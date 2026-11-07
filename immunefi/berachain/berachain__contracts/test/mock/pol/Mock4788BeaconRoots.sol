// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice A mock implementation of the EIP-4788 Beacon Roots contract.
contract Mock4788BeaconRoots {
    /// @dev flag to check if the fallback should return the root or revert
    bool public isTimestampValid = true;

    /// @dev the mock root to return
    bytes32 public mockBeaconBlockRoot;

    function setIsTimestampValid(bool status) external {
        isTimestampValid = status;
    }

    function setMockBeaconBlockRoot(bytes32 root) external {
        mockBeaconBlockRoot = root;
    }

    fallback() external {
        uint64 ts;
        assembly ("memory-safe") {
            ts := calldataload(0)
        }

        if (!isTimestampValid) {
            revert();
        }

        bytes32 root = mockBeaconBlockRoot;
        assembly ("memory-safe") {
            mstore(0, root)
            return(0, 32)
        }
    }
}
