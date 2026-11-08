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

import {
    IERC7540LikeRedeemQueuePreRequestRedeemHook
} from "src/components/issuance/interfaces/IERC7540LikeRedeemQueuePreRequestRedeemHook.sol";

/// @title ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemExtractor Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Decodes the `preRequestRedeem` payload into named policy parameters
contract ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemExtractor is IExtractor {
    string public constant override typeAndVersion =
        "ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemExtractor 1.0.0";

    /// @notice The account that called the handler to initiate the request
    bytes32 public constant PARAM_ORIGINATOR = keccak256("originator");
    bytes32 public constant PARAM_CONTROLLER = keccak256("controller");
    bytes32 public constant PARAM_OWNER = keccak256("owner");
    bytes32 public constant PARAM_SHARES_AMOUNT = keccak256("sharesAmount");

    /// @inheritdoc IExtractor
    function extract(IPolicyEngine.Payload calldata _payload) external pure returns (IPolicyEngine.Parameter[] memory) {
        require(
            _payload.selector == IERC7540LikeRedeemQueuePreRequestRedeemHook.preRequestRedeem.selector,
            IPolicyEngine.UnsupportedSelector(_payload.selector)
        );

        (address originator, address controller, address owner, uint256 sharesAmount) =
            abi.decode(_payload.data, (address, address, address, uint256));

        IPolicyEngine.Parameter[] memory result = new IPolicyEngine.Parameter[](4);
        result[0] = IPolicyEngine.Parameter(PARAM_ORIGINATOR, abi.encode(originator));
        result[1] = IPolicyEngine.Parameter(PARAM_CONTROLLER, abi.encode(controller));
        result[2] = IPolicyEngine.Parameter(PARAM_OWNER, abi.encode(owner));
        result[3] = IPolicyEngine.Parameter(PARAM_SHARES_AMOUNT, abi.encode(sharesAmount));

        return result;
    }
}
