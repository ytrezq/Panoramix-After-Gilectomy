// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

import {
    ChainlinkAceSharesTransferExtractor
} from "src/components/shares-transfer-validators/ChainlinkAceSharesTransferExtractor.sol";
import {ISharesTransferValidator} from "src/interfaces/ISharesTransferValidator.sol";

contract ChainlinkAceSharesTransferExtractorTest is Test {
    ChainlinkAceSharesTransferExtractor extractor;

    address originator = makeAddr("originator");
    address from = makeAddr("from");
    address to = makeAddr("to");
    address sender = makeAddr("sender");
    uint256 amount = 100;

    function setUp() public {
        extractor = new ChainlinkAceSharesTransferExtractor();
    }

    function test_typeAndVersion() public view {
        assertEq(extractor.typeAndVersion(), "ChainlinkAceSharesTransferExtractor 1.0.0");
    }

    function test_extract_success() public view {
        // `sender` differs from `originator` and `from` to prove the originator is read from `data`.
        IPolicyEngine.Payload memory payload = IPolicyEngine.Payload({
            selector: ISharesTransferValidator.validateSharesTransfer.selector,
            sender: sender,
            data: abi.encode(originator, from, to, amount),
            context: bytes("")
        });

        IPolicyEngine.Parameter[] memory params = extractor.extract(payload);

        assertEq(params.length, 4, "unexpected param count");

        assertEq(params[0].name, extractor.PARAM_ORIGINATOR(), "param 0 name");
        assertEq(abi.decode(params[0].value, (address)), originator, "param 0 value");

        assertEq(params[1].name, extractor.PARAM_FROM(), "param 1 name");
        assertEq(abi.decode(params[1].value, (address)), from, "param 1 value");

        assertEq(params[2].name, extractor.PARAM_TO(), "param 2 name");
        assertEq(abi.decode(params[2].value, (address)), to, "param 2 value");

        assertEq(params[3].name, extractor.PARAM_SHARES_AMOUNT(), "param 3 name");
        assertEq(abi.decode(params[3].value, (uint256)), amount, "param 3 value");
    }

    function test_extract_fail_unsupportedSelector() public {
        bytes4 badSelector = bytes4(keccak256("notSharesTransfer()"));

        IPolicyEngine.Payload memory payload = IPolicyEngine.Payload({
            selector: badSelector, sender: sender, data: abi.encode(from, to, amount, sender), context: bytes("")
        });

        vm.expectRevert(abi.encodeWithSelector(IPolicyEngine.UnsupportedSelector.selector, badSelector));
        extractor.extract(payload);
    }
}
