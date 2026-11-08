// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

import {ISharesMintHandlerPreMintHook} from "src/components/issuance/interfaces/ISharesMintHandlerPreMintHook.sol";

import {
    ChainlinkAceSharesMintHandlerPreMintValidatorHarness
} from "test/harnesses/ChainlinkAceSharesMintHandlerPreMintValidatorHarness.sol";
import {ChainlinkAceIssuanceValidatorTestBase} from "test/utils/ChainlinkAceIssuanceValidatorTestBase.sol";

contract ChainlinkAceSharesMintHandlerPreMintValidatorTest is ChainlinkAceIssuanceValidatorTestBase {
    address originator = makeAddr("originator");
    address recipient = makeAddr("recipient");
    uint256 sharesAmount = 123;

    function __deployValidator(address shares_) internal override returns (address) {
        return address(new ChainlinkAceSharesMintHandlerPreMintValidatorHarness(shares_));
    }

    function __callEntrypoint(address validator_) internal override {
        ChainlinkAceSharesMintHandlerPreMintValidatorHarness(validator_).preMint({
            _originator: originator, _to: recipient, _sharesAmount: sharesAmount
        });
    }

    function __expectedPayload(bytes memory context_) internal view override returns (IPolicyEngine.Payload memory) {
        return IPolicyEngine.Payload({
            selector: ISharesMintHandlerPreMintHook.preMint.selector,
            sender: handler,
            data: abi.encode(originator, recipient, sharesAmount),
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
