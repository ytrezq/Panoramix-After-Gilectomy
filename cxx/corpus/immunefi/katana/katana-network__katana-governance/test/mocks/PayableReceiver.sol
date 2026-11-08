// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @notice Mock contract that accepts ETH for testing payable functions
contract PayableReceiver {
    event EthReceived(address sender, uint256 amount);

    receive() external payable {
        emit EthReceived(msg.sender, msg.value);
    }

    function receiveEth() external payable {
        emit EthReceived(msg.sender, msg.value);
    }

    /// @notice Receives ETH and sends a portion back to the sender
    /// @param amountToReturn The amount of ETH to send back to msg.sender
    function receiveEthAndReturnSome(uint256 amountToReturn) external payable {
        emit EthReceived(msg.sender, msg.value);
        require(amountToReturn <= msg.value, "Cannot return more than received");
        if (amountToReturn > 0) {
            (bool success,) = msg.sender.call{ value: amountToReturn }("");
            require(success, "ETH return failed");
        }
    }
}
