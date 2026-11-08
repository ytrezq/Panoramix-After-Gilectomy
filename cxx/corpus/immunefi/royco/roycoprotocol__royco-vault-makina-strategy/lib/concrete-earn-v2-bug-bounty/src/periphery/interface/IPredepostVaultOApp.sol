// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {
    MessagingFee,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

interface IPredepostVaultOApp {
    /**
     * @notice Returns the vault address
     * @return The address of the authorized vault
     */
    function vault() external view returns (address);

    /**
     * @notice Returns the destination endpoint ID
     * @return The destination endpoint ID
     */
    function dstEid() external view returns (uint32);

    /**
     * @notice Set the destination endpoint ID
     * @param _dstEid The destination endpoint ID
     * @dev Only callable by owner
     */
    function setDstEid(uint32 _dstEid) external;

    /**
     * @notice Send a LayerZero message (only callable by vault)
     * @dev Quotes the fee internally and validates msg.value is sufficient
     * @dev Uses the stored dstEid
     * @param payload Message payload
     * @param options LayerZero options
     * @param refundAddress Address to refund excess fee
     */
    function send(bytes calldata payload, bytes calldata options, address refundAddress)
        external
        payable
        returns (MessagingReceipt memory receipt);

    /**
     * @notice Quote the fee for sending a message (view function - no vault restriction)
     * @dev Uses the stored dstEid
     * @param payload Message payload
     * @param options LayerZero options
     * @param payInLzToken Whether to pay in LZ token
     * @return fee The estimated messaging fee
     */
    function quote(bytes calldata payload, bytes calldata options, bool payInLzToken)
        external
        view
        returns (MessagingFee memory fee);

    /**
     * @notice Quote the fee for claiming shares on target chain
     * @param user The user address to claim for
     * @param options LayerZero messaging options
     * @param payInLzToken Whether to pay in LZ token
     * @return fee The estimated messaging fee
     */
    function quoteClaimOnTargetChain(address user, bytes calldata options, bool payInLzToken)
        external
        view
        returns (MessagingFee memory fee);

    /**
     * @notice Quote the fee for batch claiming shares on target chain
     * @param addressesData Encoded array of addresses to claim for
     * @param options LayerZero messaging options
     * @param payInLzToken Whether to pay in LZ token
     * @return fee The estimated messaging fee
     */
    function quoteBatchClaimOnTargetChain(bytes calldata addressesData, bytes calldata options, bool payInLzToken)
        external
        view
        returns (MessagingFee memory fee);
}

