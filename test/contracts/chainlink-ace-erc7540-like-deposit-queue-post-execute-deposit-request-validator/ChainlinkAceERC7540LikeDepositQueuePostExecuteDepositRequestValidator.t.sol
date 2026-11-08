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
    IERC7540LikeDepositQueuePostExecuteDepositRequestHook
} from "src/components/issuance/interfaces/IERC7540LikeDepositQueuePostExecuteDepositRequestHook.sol";

import {
    ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestValidatorHarness
} from "test/harnesses/ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestValidatorHarness.sol";
import {ChainlinkAceIssuanceValidatorTestBase} from "test/utils/ChainlinkAceIssuanceValidatorTestBase.sol";

contract ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestValidatorTest is
    ChainlinkAceIssuanceValidatorTestBase
{
    address originator = makeAddr("originator");
    address controller = makeAddr("controller");
    address owner = makeAddr("owner");
    uint256 sharesAmount = 123;
    uint256 assetAmount = 456;

    function __deployValidator(address shares_) internal override returns (address) {
        return address(new ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestValidatorHarness(shares_));
    }

    function __callEntrypoint(address validator_) internal override {
        ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestValidatorHarness(validator_)
            .postExecuteDepositRequest({
                _originator: originator,
                _controller: controller,
                _owner: owner,
                _sharesAmount: sharesAmount,
                _assetAmount: assetAmount
            });
    }

    function __expectedPayload(bytes memory context_) internal view override returns (IPolicyEngine.Payload memory) {
        return IPolicyEngine.Payload({
            selector: IERC7540LikeDepositQueuePostExecuteDepositRequestHook.postExecuteDepositRequest.selector,
            sender: handler,
            data: abi.encode(originator, controller, owner, sharesAmount, assetAmount),
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
