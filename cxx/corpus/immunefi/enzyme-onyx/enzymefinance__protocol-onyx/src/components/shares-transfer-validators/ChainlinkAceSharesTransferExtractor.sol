// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IExtractor} from "@chainlink/policy-management/interfaces/IExtractor.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

import {ISharesTransferValidator} from "src/interfaces/ISharesTransferValidator.sol";

/// @title ChainlinkAceSharesTransferExtractor Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Decodes the payload emitted by `ChainlinkAceSharesTransferValidator` into the named policy parameters
contract ChainlinkAceSharesTransferExtractor is IExtractor {
    /// @notice Type and version of the extractor
    string public constant override typeAndVersion = "ChainlinkAceSharesTransferExtractor 1.0.0";

    /// @notice Parameter key for the shares transfer sender
    bytes32 public constant PARAM_FROM = keccak256("from");

    /// @notice Parameter key for the shares transfer recipient
    bytes32 public constant PARAM_TO = keccak256("to");

    /// @notice Parameter key for the shares transfer amount
    bytes32 public constant PARAM_SHARES_AMOUNT = keccak256("sharesAmount");

    /// @notice Parameter key for the shares transfer originator, i.e., the account that called the protocol
    /// contract to initiate the action
    bytes32 public constant PARAM_ORIGINATOR = keccak256("originator");

    /// @inheritdoc IExtractor
    function extract(IPolicyEngine.Payload calldata _payload) external pure returns (IPolicyEngine.Parameter[] memory) {
        require(
            _payload.selector == ISharesTransferValidator.validateSharesTransfer.selector,
            IPolicyEngine.UnsupportedSelector(_payload.selector)
        );

        (address originator, address from, address to, uint256 amount) =
            abi.decode(_payload.data, (address, address, address, uint256));

        IPolicyEngine.Parameter[] memory result = new IPolicyEngine.Parameter[](4);
        result[0] = IPolicyEngine.Parameter(PARAM_ORIGINATOR, abi.encode(originator));
        result[1] = IPolicyEngine.Parameter(PARAM_FROM, abi.encode(from));
        result[2] = IPolicyEngine.Parameter(PARAM_TO, abi.encode(to));
        result[3] = IPolicyEngine.Parameter(PARAM_SHARES_AMOUNT, abi.encode(amount));

        return result;
    }
}
