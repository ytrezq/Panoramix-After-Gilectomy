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
    IERC7540LikeRedeemQueuePreRequestRedeemHook
} from "src/components/issuance/interfaces/IERC7540LikeRedeemQueuePreRequestRedeemHook.sol";

import {
    ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidatorHarness
} from "test/harnesses/ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidatorHarness.sol";
import {ChainlinkAceIssuanceValidatorTestBase} from "test/utils/ChainlinkAceIssuanceValidatorTestBase.sol";

contract ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidatorTest is ChainlinkAceIssuanceValidatorTestBase {
    address originator = makeAddr("originator");
    address controller = makeAddr("controller");
    address owner = makeAddr("owner");
    uint256 sharesAmount = 123;

    function __deployValidator(address shares_) internal override returns (address) {
        return address(new ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidatorHarness(shares_));
    }

    function __callEntrypoint(address validator_) internal override {
        ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidatorHarness(validator_).preRequestRedeem({
            _originator: originator, _controller: controller, _owner: owner, _sharesAmount: sharesAmount
        });
    }

    function __expectedPayload(bytes memory context_) internal view override returns (IPolicyEngine.Payload memory) {
        return IPolicyEngine.Payload({
            selector: IERC7540LikeRedeemQueuePreRequestRedeemHook.preRequestRedeem.selector,
            sender: handler,
            data: abi.encode(originator, controller, owner, sharesAmount),
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
