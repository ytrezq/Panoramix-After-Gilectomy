// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

import {ISharesBurnHandlerPreBurnHook} from "src/components/issuance/interfaces/ISharesBurnHandlerPreBurnHook.sol";

import {
    ChainlinkAceSharesBurnHandlerPreBurnValidatorHarness
} from "test/harnesses/ChainlinkAceSharesBurnHandlerPreBurnValidatorHarness.sol";
import {ChainlinkAceIssuanceValidatorTestBase} from "test/utils/ChainlinkAceIssuanceValidatorTestBase.sol";

contract ChainlinkAceSharesBurnHandlerPreBurnValidatorTest is ChainlinkAceIssuanceValidatorTestBase {
    address originator = makeAddr("originator");
    address holder = makeAddr("holder");
    uint256 sharesAmount = 123;

    function __deployValidator(address shares_) internal override returns (address) {
        return address(new ChainlinkAceSharesBurnHandlerPreBurnValidatorHarness(shares_));
    }

    function __callEntrypoint(address validator_) internal override {
        ChainlinkAceSharesBurnHandlerPreBurnValidatorHarness(validator_).preBurn({
            _originator: originator, _from: holder, _sharesAmount: sharesAmount
        });
    }

    function __expectedPayload(bytes memory context_) internal view override returns (IPolicyEngine.Payload memory) {
        return IPolicyEngine.Payload({
            selector: ISharesBurnHandlerPreBurnHook.preBurn.selector,
            sender: handler,
            data: abi.encode(originator, holder, sharesAmount),
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
