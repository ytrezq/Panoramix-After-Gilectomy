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
    ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemExtractor
} from "src/components/issuance/hooks/chainlink-ace/extractors/ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemExtractor.sol";
import {
    IERC7540LikeDepositQueuePreRequestDepositHook
} from "src/components/issuance/interfaces/IERC7540LikeDepositQueuePreRequestDepositHook.sol";
import {
    IERC7540LikeRedeemQueuePreRequestRedeemHook
} from "src/components/issuance/interfaces/IERC7540LikeRedeemQueuePreRequestRedeemHook.sol";

contract ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemExtractorTest is Test {
    ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemExtractor extractor;

    address originator = makeAddr("originator");
    address controller = makeAddr("controller");
    address owner = makeAddr("owner");
    address sender = makeAddr("sender");
    uint256 sharesAmount = 100;

    function setUp() public {
        extractor = new ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemExtractor();
    }

    function test_typeAndVersion() public view {
        assertEq(extractor.typeAndVersion(), "ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemExtractor 1.0.0");
    }

    function test_extract_success() public view {
        IPolicyEngine.Payload memory payload = IPolicyEngine.Payload({
            selector: IERC7540LikeRedeemQueuePreRequestRedeemHook.preRequestRedeem.selector,
            sender: sender,
            data: abi.encode(originator, controller, owner, sharesAmount),
            context: bytes("")
        });

        IPolicyEngine.Parameter[] memory params = extractor.extract(payload);

        assertEq(params.length, 4, "unexpected param count");

        assertEq(params[0].name, extractor.PARAM_ORIGINATOR(), "param 0 name");
        assertEq(abi.decode(params[0].value, (address)), originator, "param 0 value");

        assertEq(params[1].name, extractor.PARAM_CONTROLLER(), "param 1 name");
        assertEq(abi.decode(params[1].value, (address)), controller, "param 1 value");

        assertEq(params[2].name, extractor.PARAM_OWNER(), "param 2 name");
        assertEq(abi.decode(params[2].value, (address)), owner, "param 2 value");

        assertEq(params[3].name, extractor.PARAM_SHARES_AMOUNT(), "param 3 name");
        assertEq(abi.decode(params[3].value, (uint256)), sharesAmount, "param 3 value");
    }

    function test_extract_fail_unsupportedSelector() public {
        bytes4 badSelector = bytes4(keccak256("notIssuanceAction()"));

        __test_extract_fail_unsupportedSelector(badSelector);
    }

    function test_extract_fail_unsupportedSelector_preRequestDeposit() public {
        // The sibling pre-request selector shares the calldata shape but has its own extractor.
        __test_extract_fail_unsupportedSelector(
            IERC7540LikeDepositQueuePreRequestDepositHook.preRequestDeposit.selector
        );
    }

    function __test_extract_fail_unsupportedSelector(bytes4 _selector) internal {
        IPolicyEngine.Payload memory payload = IPolicyEngine.Payload({
            selector: _selector,
            sender: sender,
            data: abi.encode(originator, controller, owner, sharesAmount),
            context: bytes("")
        });

        vm.expectRevert(abi.encodeWithSelector(IPolicyEngine.UnsupportedSelector.selector, _selector));
        extractor.extract(payload);
    }
}
