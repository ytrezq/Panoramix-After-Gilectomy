// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

import {
    ISyncDepositHandlerPostDepositHook
} from "src/components/issuance/interfaces/ISyncDepositHandlerPostDepositHook.sol";

import {
    ChainlinkAceSyncDepositHandlerPostDepositValidatorHarness
} from "test/harnesses/ChainlinkAceSyncDepositHandlerPostDepositValidatorHarness.sol";
import {ChainlinkAceIssuanceValidatorTestBase} from "test/utils/ChainlinkAceIssuanceValidatorTestBase.sol";

contract ChainlinkAceSyncDepositHandlerPostDepositValidatorTest is ChainlinkAceIssuanceValidatorTestBase {
    address originator = makeAddr("originator");
    uint256 sharesAmount = 123;
    uint256 assetAmount = 456;

    function __deployValidator(address shares_) internal override returns (address) {
        return address(new ChainlinkAceSyncDepositHandlerPostDepositValidatorHarness(shares_));
    }

    function __callEntrypoint(address validator_) internal override {
        ChainlinkAceSyncDepositHandlerPostDepositValidatorHarness(validator_).postDeposit({
            _originator: originator, _sharesAmount: sharesAmount, _assetAmount: assetAmount
        });
    }

    function __expectedPayload(bytes memory context_) internal view override returns (IPolicyEngine.Payload memory) {
        return IPolicyEngine.Payload({
            selector: ISyncDepositHandlerPostDepositHook.postDeposit.selector,
            sender: handler,
            data: abi.encode(originator, sharesAmount, assetAmount),
            context: context_
        });
    }

    function test_WhenTheCallerIsNotTheHandler() external {
        __assertRevertsWhenCallerNotHandler();
    }

    function test_GivenThePolicyEngineRejectsTheRun() external {
        __assertRevertsWhenPolicyRejects();
    }
}
