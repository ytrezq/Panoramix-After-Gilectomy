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
    ChainlinkAceSharesBurnHandlerPreBurnExtractor
} from "src/components/issuance/hooks/chainlink-ace/extractors/ChainlinkAceSharesBurnHandlerPreBurnExtractor.sol";
import {ISharesBurnHandlerPreBurnHook} from "src/components/issuance/interfaces/ISharesBurnHandlerPreBurnHook.sol";
import {ISharesMintHandlerPreMintHook} from "src/components/issuance/interfaces/ISharesMintHandlerPreMintHook.sol";

contract ChainlinkAceSharesBurnHandlerPreBurnExtractorTest is Test {
    ChainlinkAceSharesBurnHandlerPreBurnExtractor extractor;

    address originator = makeAddr("originator");
    address from = makeAddr("from");
    address sender = makeAddr("sender");
    uint256 sharesAmount = 100;

    function setUp() public {
        extractor = new ChainlinkAceSharesBurnHandlerPreBurnExtractor();
    }

    function test_typeAndVersion() public view {
        assertEq(extractor.typeAndVersion(), "ChainlinkAceSharesBurnHandlerPreBurnExtractor 1.0.0");
    }

    function test_extract_success() public view {
        IPolicyEngine.Payload memory payload = IPolicyEngine.Payload({
            selector: ISharesBurnHandlerPreBurnHook.preBurn.selector,
            sender: sender,
            data: abi.encode(originator, from, sharesAmount),
            context: bytes("")
        });

        IPolicyEngine.Parameter[] memory params = extractor.extract(payload);

        assertEq(params.length, 3, "unexpected param count");

        assertEq(params[0].name, extractor.PARAM_ORIGINATOR(), "param 0 name");
        assertEq(abi.decode(params[0].value, (address)), originator, "param 0 value");

        assertEq(params[1].name, extractor.PARAM_FROM(), "param 1 name");
        assertEq(abi.decode(params[1].value, (address)), from, "param 1 value");

        assertEq(params[2].name, extractor.PARAM_SHARES_AMOUNT(), "param 2 name");
        assertEq(abi.decode(params[2].value, (uint256)), sharesAmount, "param 2 value");
    }

    function test_extract_fail_unsupportedSelector() public {
        bytes4 badSelector = bytes4(keccak256("notBurnAction()"));

        __test_extract_fail_unsupportedSelector(badSelector);
    }

    function test_extract_fail_unsupportedSelector_preMint() public {
        // The sibling mint/burn selector shares the calldata shape but has its own extractor.
        __test_extract_fail_unsupportedSelector(ISharesMintHandlerPreMintHook.preMint.selector);
    }

    function __test_extract_fail_unsupportedSelector(bytes4 _selector) internal {
        IPolicyEngine.Payload memory payload = IPolicyEngine.Payload({
            selector: _selector, sender: sender, data: abi.encode(originator, from, sharesAmount), context: bytes("")
        });

        vm.expectRevert(abi.encodeWithSelector(IPolicyEngine.UnsupportedSelector.selector, _selector));
        extractor.extract(payload);
    }
}
