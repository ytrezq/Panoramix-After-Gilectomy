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
    IERC7540LikeRedeemQueuePostExecuteRedeemRequestHook
} from "src/components/issuance/interfaces/IERC7540LikeRedeemQueuePostExecuteRedeemRequestHook.sol";

/// @title ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestExtractor Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Decodes the `postExecuteRedeemRequest` payload into named policy parameters
contract ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestExtractor is IExtractor {
    string public constant override typeAndVersion =
        "ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestExtractor 1.0.0";

    /// @notice The account that called the handler to initiate the action
    bytes32 public constant PARAM_ORIGINATOR = keccak256("originator");
    bytes32 public constant PARAM_CONTROLLER = keccak256("controller");
    bytes32 public constant PARAM_OWNER = keccak256("owner");
    bytes32 public constant PARAM_SHARES_AMOUNT = keccak256("sharesAmount");
    bytes32 public constant PARAM_ASSET_AMOUNT = keccak256("assetAmount");

    /// @inheritdoc IExtractor
    function extract(IPolicyEngine.Payload calldata _payload) external pure returns (IPolicyEngine.Parameter[] memory) {
        require(
            _payload.selector == IERC7540LikeRedeemQueuePostExecuteRedeemRequestHook.postExecuteRedeemRequest.selector,
            IPolicyEngine.UnsupportedSelector(_payload.selector)
        );

        (address originator, address controller, address owner, uint256 sharesAmount, uint256 assetAmount) =
            abi.decode(_payload.data, (address, address, address, uint256, uint256));

        IPolicyEngine.Parameter[] memory result = new IPolicyEngine.Parameter[](5);
        result[0] = IPolicyEngine.Parameter(PARAM_ORIGINATOR, abi.encode(originator));
        result[1] = IPolicyEngine.Parameter(PARAM_CONTROLLER, abi.encode(controller));
        result[2] = IPolicyEngine.Parameter(PARAM_OWNER, abi.encode(owner));
        result[3] = IPolicyEngine.Parameter(PARAM_SHARES_AMOUNT, abi.encode(sharesAmount));
        result[4] = IPolicyEngine.Parameter(PARAM_ASSET_AMOUNT, abi.encode(assetAmount));

        return result;
    }
}
