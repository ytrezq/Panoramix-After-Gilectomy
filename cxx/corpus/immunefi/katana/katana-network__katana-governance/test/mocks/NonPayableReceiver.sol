// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @notice Mock contract that rejects ETH transfers for testing non-payable scenarios
contract NonPayableReceiver {
// This contract has no receive() or fallback() function
// Any attempt to send ETH to it will fail
}
