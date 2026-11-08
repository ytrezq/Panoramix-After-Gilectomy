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
    ISyncRedeemHandlerPostRedeemHook
} from "src/components/issuance/interfaces/ISyncRedeemHandlerPostRedeemHook.sol";

/// @title ChainlinkAceSyncRedeemHandlerPostRedeemExtractor Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Decodes the `postRedeem` payload into named policy parameters
contract ChainlinkAceSyncRedeemHandlerPostRedeemExtractor is IExtractor {
    string public constant override typeAndVersion = "ChainlinkAceSyncRedeemHandlerPostRedeemExtractor 1.0.0";

    /// @notice The account that called the handler to redeem, which is also the payee
    bytes32 public constant PARAM_ORIGINATOR = keccak256("originator");
    /// @notice The gross shares burned, including exit-fee shares
    bytes32 public constant PARAM_SHARES_AMOUNT = keccak256("sharesAmount");
    /// @notice The assets paid to the originator, net of the exit fee
    bytes32 public constant PARAM_ASSET_AMOUNT = keccak256("assetAmount");

    /// @inheritdoc IExtractor
    function extract(IPolicyEngine.Payload calldata _payload) external pure returns (IPolicyEngine.Parameter[] memory) {
        require(
            _payload.selector == ISyncRedeemHandlerPostRedeemHook.postRedeem.selector,
            IPolicyEngine.UnsupportedSelector(_payload.selector)
        );

        (address originator, uint256 sharesAmount, uint256 assetAmount) =
            abi.decode(_payload.data, (address, uint256, uint256));

        IPolicyEngine.Parameter[] memory result = new IPolicyEngine.Parameter[](3);
        result[0] = IPolicyEngine.Parameter({name: PARAM_ORIGINATOR, value: abi.encode(originator)});
        result[1] = IPolicyEngine.Parameter({name: PARAM_SHARES_AMOUNT, value: abi.encode(sharesAmount)});
        result[2] = IPolicyEngine.Parameter({name: PARAM_ASSET_AMOUNT, value: abi.encode(assetAmount)});

        return result;
    }
}
