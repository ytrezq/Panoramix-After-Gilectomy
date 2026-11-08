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

import {ISharesBurnHandlerPreBurnHook} from "src/components/issuance/interfaces/ISharesBurnHandlerPreBurnHook.sol";

/// @title ChainlinkAceSharesBurnHandlerPreBurnExtractor Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Decodes the `preBurn` payload into named policy parameters
contract ChainlinkAceSharesBurnHandlerPreBurnExtractor is IExtractor {
    string public constant override typeAndVersion = "ChainlinkAceSharesBurnHandlerPreBurnExtractor 1.0.0";

    /// @notice The account that called the handler to initiate the burn
    bytes32 public constant PARAM_ORIGINATOR = keccak256("originator");
    bytes32 public constant PARAM_FROM = keccak256("from");
    bytes32 public constant PARAM_SHARES_AMOUNT = keccak256("sharesAmount");

    /// @inheritdoc IExtractor
    function extract(IPolicyEngine.Payload calldata _payload) external pure returns (IPolicyEngine.Parameter[] memory) {
        require(
            _payload.selector == ISharesBurnHandlerPreBurnHook.preBurn.selector,
            IPolicyEngine.UnsupportedSelector(_payload.selector)
        );

        (address originator, address from, uint256 sharesAmount) =
            abi.decode(_payload.data, (address, address, uint256));

        IPolicyEngine.Parameter[] memory result = new IPolicyEngine.Parameter[](3);
        result[0] = IPolicyEngine.Parameter(PARAM_ORIGINATOR, abi.encode(originator));
        result[1] = IPolicyEngine.Parameter(PARAM_FROM, abi.encode(from));
        result[2] = IPolicyEngine.Parameter(PARAM_SHARES_AMOUNT, abi.encode(sharesAmount));

        return result;
    }
}
