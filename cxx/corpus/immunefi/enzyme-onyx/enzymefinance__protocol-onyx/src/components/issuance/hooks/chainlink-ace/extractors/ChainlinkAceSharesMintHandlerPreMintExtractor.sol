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

import {ISharesMintHandlerPreMintHook} from "src/components/issuance/interfaces/ISharesMintHandlerPreMintHook.sol";

/// @title ChainlinkAceSharesMintHandlerPreMintExtractor Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Decodes the `preMint` payload into named policy parameters
contract ChainlinkAceSharesMintHandlerPreMintExtractor is IExtractor {
    string public constant override typeAndVersion = "ChainlinkAceSharesMintHandlerPreMintExtractor 1.0.0";

    /// @notice The account that called the handler to initiate the mint
    bytes32 public constant PARAM_ORIGINATOR = keccak256("originator");
    bytes32 public constant PARAM_TO = keccak256("to");
    bytes32 public constant PARAM_SHARES_AMOUNT = keccak256("sharesAmount");

    /// @inheritdoc IExtractor
    function extract(IPolicyEngine.Payload calldata _payload) external pure returns (IPolicyEngine.Parameter[] memory) {
        require(
            _payload.selector == ISharesMintHandlerPreMintHook.preMint.selector,
            IPolicyEngine.UnsupportedSelector(_payload.selector)
        );

        (address originator, address to, uint256 sharesAmount) = abi.decode(_payload.data, (address, address, uint256));

        IPolicyEngine.Parameter[] memory result = new IPolicyEngine.Parameter[](3);
        result[0] = IPolicyEngine.Parameter(PARAM_ORIGINATOR, abi.encode(originator));
        result[1] = IPolicyEngine.Parameter(PARAM_TO, abi.encode(to));
        result[2] = IPolicyEngine.Parameter(PARAM_SHARES_AMOUNT, abi.encode(sharesAmount));

        return result;
    }
}
