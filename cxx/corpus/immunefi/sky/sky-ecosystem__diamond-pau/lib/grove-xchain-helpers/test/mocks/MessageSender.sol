// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { ILayerZeroEndpointV2, LZForwarder } from "src/forwarders/LZForwarder.sol";

/**
 * @title MessageSender
 * @notice Simple contract that can send LayerZero messages and configure itself
 * @dev Used in tests to make authority addresses actual senders rather than just refund addresses
 */
contract MessageSender {

    /**
     * @notice Configure this contract as a sender for cross-chain communication
     * @param endpoint The LayerZero endpoint address
     * @param remoteEid The destination endpoint ID
     * @param dvns The DVNs to use for verification
     */
    function configureSender(
        address   endpoint,
        uint32    remoteEid,
        address[] memory dvns,
        address   executor
    ) external {
        LZForwarder.configureSender(endpoint, remoteEid, dvns, executor);
    }

    /**
     * @notice Send a LayerZero message
     * @param _dstEid Destination endpoint ID
     * @param _receiver Receiver address (as bytes32)
     * @param endpoint The LayerZero endpoint
     * @param _message The message to send
     * @param _options LayerZero options
     * @param _refundAddress Address to receive refunds
     * @param _payInLzToken Whether to pay in LZ token
     */
    function sendMessage(
        uint32  _dstEid,
        bytes32 _receiver,
        address endpoint,
        bytes   memory _message,
        bytes   memory _options,
        address _refundAddress,
        bool    _payInLzToken
    ) external payable {
        // Use LZForwarder library - it will execute in this contract's context
        // The library will call endpoint.send{value:...} which will use this contract's balance
        LZForwarder.sendMessage(
            _dstEid,
            _receiver,
            ILayerZeroEndpointV2(endpoint),
            _message,
            _options,
            _refundAddress,
            _payInLzToken
        );
    }

    // Allow receiving ETH
    receive() external payable {}
}

