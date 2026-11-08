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
    ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestExtractor
} from "src/components/issuance/hooks/chainlink-ace/extractors/ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestExtractor.sol";
import {
    IERC7540LikeDepositQueuePostExecuteDepositRequestHook
} from "src/components/issuance/interfaces/IERC7540LikeDepositQueuePostExecuteDepositRequestHook.sol";
import {
    IERC7540LikeRedeemQueuePostExecuteRedeemRequestHook
} from "src/components/issuance/interfaces/IERC7540LikeRedeemQueuePostExecuteRedeemRequestHook.sol";
import {
    ISyncDepositHandlerPostDepositHook
} from "src/components/issuance/interfaces/ISyncDepositHandlerPostDepositHook.sol";

contract ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestExtractorTest is Test {
    ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestExtractor extractor;

    address originator = makeAddr("originator");
    address controller = makeAddr("controller");
    address owner = makeAddr("owner");
    address sender = makeAddr("sender");
    uint256 sharesAmount = 100;
    uint256 assetAmount = 200;

    function setUp() public {
        extractor = new ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestExtractor();
    }

    function test_typeAndVersion() public view {
        assertEq(
            extractor.typeAndVersion(), "ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestExtractor 1.0.0"
        );
    }

    function test_extract_success() public view {
        IPolicyEngine.Payload memory payload = IPolicyEngine.Payload({
            selector: IERC7540LikeDepositQueuePostExecuteDepositRequestHook.postExecuteDepositRequest.selector,
            sender: sender,
            data: abi.encode(originator, controller, owner, sharesAmount, assetAmount),
            context: bytes("")
        });

        IPolicyEngine.Parameter[] memory params = extractor.extract(payload);

        assertEq(params.length, 5, "unexpected param count");

        assertEq(params[0].name, extractor.PARAM_ORIGINATOR(), "param 0 name");
        assertEq(abi.decode(params[0].value, (address)), originator, "param 0 value");

        assertEq(params[1].name, extractor.PARAM_CONTROLLER(), "param 1 name");
        assertEq(abi.decode(params[1].value, (address)), controller, "param 1 value");

        assertEq(params[2].name, extractor.PARAM_OWNER(), "param 2 name");
        assertEq(abi.decode(params[2].value, (address)), owner, "param 2 value");

        assertEq(params[3].name, extractor.PARAM_SHARES_AMOUNT(), "param 3 name");
        assertEq(abi.decode(params[3].value, (uint256)), sharesAmount, "param 3 value");

        assertEq(params[4].name, extractor.PARAM_ASSET_AMOUNT(), "param 4 name");
        assertEq(abi.decode(params[4].value, (uint256)), assetAmount, "param 4 value");
    }

    function test_extract_fail_unsupportedSelector() public {
        bytes4 badSelector = bytes4(keccak256("notPostExecuteDepositRequest()"));

        __test_extract_fail_unsupportedSelector(badSelector);
    }

    function test_extract_fail_unsupportedSelector_postDeposit() public {
        // The sibling post-issuance selectors share the calldata shape but have their own extractors.
        __test_extract_fail_unsupportedSelector(ISyncDepositHandlerPostDepositHook.postDeposit.selector);
    }

    function test_extract_fail_unsupportedSelector_postExecuteRedeemRequest() public {
        __test_extract_fail_unsupportedSelector(
            IERC7540LikeRedeemQueuePostExecuteRedeemRequestHook.postExecuteRedeemRequest.selector
        );
    }

    function __test_extract_fail_unsupportedSelector(bytes4 _selector) internal {
        IPolicyEngine.Payload memory payload = IPolicyEngine.Payload({
            selector: _selector,
            sender: sender,
            data: abi.encode(originator, controller, owner, sharesAmount, assetAmount),
            context: bytes("")
        });

        vm.expectRevert(abi.encodeWithSelector(IPolicyEngine.UnsupportedSelector.selector, _selector));
        extractor.extract(payload);
    }
}
