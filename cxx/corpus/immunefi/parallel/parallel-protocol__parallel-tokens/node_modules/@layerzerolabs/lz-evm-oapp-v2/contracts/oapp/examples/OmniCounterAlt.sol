// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ILayerZeroEndpointV2, MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { OAppSender } from "../OAppSender.sol";

import { OmniCounterAbstract, MsgCodec } from "./OmniCounterAbstract.sol";

/**
 * @title OmniCounterAlt
 * @dev OmniCounter variant for EndpointV2Alt where the native fee is paid in ERC20 token.
 * @dev Unaudited contract. Use at your own risk.
 */
contract OmniCounterAlt is OmniCounterAbstract {
    using MsgCodec for bytes;
    using SafeERC20 for IERC20;

    /// @notice ERC20 token used by EndpointV2Alt as the native fee token.
    address public immutable feeToken;

    error OmniCounterAlt_NotAnAltEndpoint();
    error OmniCounterAlt_OnlyAltToken();

    constructor(address _endpoint, address _delegate) OmniCounterAbstract(_endpoint, _delegate) {
        feeToken = ILayerZeroEndpointV2(_endpoint).nativeToken();
        if (feeToken == address(0)) revert OmniCounterAlt_NotAnAltEndpoint();
    }

    /// @dev Override to withdraw ERC20 fee instead of native ETH.
    function withdraw(address payable _to, uint256 _amount) external virtual override onlyAdmin {
        IERC20(feeToken).safeTransfer(_to, _amount);
    }

    /// @dev Override to quote actual fee instead of relying on msg.value.
    function batchIncrement(
        uint32[] calldata _eids,
        uint8[] calldata _types,
        bytes[] calldata _options
    ) external payable virtual override {
        require(_eids.length == _options.length && _eids.length == _types.length, "OmniCounter: length mismatch");

        for (uint256 i = 0; i < _eids.length; i++) {
            uint32 dstEid = _eids[i];

            bytes memory message = MsgCodec.encode(_types[i], eid);
            MessagingFee memory fee = _quote(dstEid, message, _options[i], false);

            OAppSender._lzSend(dstEid, message, _options[i], fee, msg.sender);
            _incrementOutbound(dstEid);
        }
    }

    /// @dev Override to quote actual fee since parent passes msg.value (which is 0 for Alt).
    function _lzSend(
        uint32 _dstEid,
        bytes memory _message,
        bytes memory _options,
        MessagingFee memory _fee,
        address _refundAddress
    ) internal virtual override returns (MessagingReceipt memory receipt) {
        MessagingFee memory actualFee = _quote(_dstEid, _message, _options, _fee.lzTokenFee > 0);
        return super._lzSend(_dstEid, _message, _options, actualFee, _refundAddress);
    }

    /// @dev Transfer ERC20 fee to endpoint instead of native ETH.
    function _payNative(uint256 _nativeFee) internal override returns (uint256) {
        if (msg.value != 0) revert OmniCounterAlt_OnlyAltToken();
        if (_nativeFee > 0) {
            if (msg.sender == address(endpoint)) {
                // ABA reply or compose callback - contract pays from its balance
                IERC20(feeToken).safeTransfer(address(endpoint), _nativeFee);
            } else {
                // User-initiated - user pays (must have approved this contract)
                IERC20(feeToken).safeTransferFrom(msg.sender, address(endpoint), _nativeFee);
            }
        }
        return 0;
    }

    /// @dev Override to avoid receiving native ETH.
    receive() external payable virtual override {
        revert OmniCounterAlt_OnlyAltToken();
    }

    /// @dev Override to avoid receiving native ETH.
    fallback() external payable virtual override {
        revert OmniCounterAlt_OnlyAltToken();
    }
}
