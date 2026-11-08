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
    ChainlinkAceSyncDepositHandlerPostDepositExtractor
} from "src/components/issuance/hooks/chainlink-ace/extractors/ChainlinkAceSyncDepositHandlerPostDepositExtractor.sol";
import {
    IERC7540LikeDepositQueuePostExecuteDepositRequestHook
} from "src/components/issuance/interfaces/IERC7540LikeDepositQueuePostExecuteDepositRequestHook.sol";
import {
    IERC7540LikeRedeemQueuePostExecuteRedeemRequestHook
} from "src/components/issuance/interfaces/IERC7540LikeRedeemQueuePostExecuteRedeemRequestHook.sol";
import {
    ISyncDepositHandlerPostDepositHook
} from "src/components/issuance/interfaces/ISyncDepositHandlerPostDepositHook.sol";

contract ChainlinkAceSyncDepositHandlerPostDepositExtractorTest is Test {
    ChainlinkAceSyncDepositHandlerPostDepositExtractor extractor;

    address originator = makeAddr("originator");
    address sender = makeAddr("sender");
    uint256 sharesAmount = 100;
    uint256 assetAmount = 200;

    function setUp() public {
        extractor = new ChainlinkAceSyncDepositHandlerPostDepositExtractor();
    }

    function test_typeAndVersion() public view {
        assertEq(extractor.typeAndVersion(), "ChainlinkAceSyncDepositHandlerPostDepositExtractor 1.0.0");
    }

    function test_extract_success() public view {
        IPolicyEngine.Payload memory payload = IPolicyEngine.Payload({
            selector: ISyncDepositHandlerPostDepositHook.postDeposit.selector,
            sender: sender,
            data: abi.encode(originator, sharesAmount, assetAmount),
            context: bytes("")
        });

        IPolicyEngine.Parameter[] memory params = extractor.extract(payload);

        assertEq(params.length, 3, "unexpected param count");

        assertEq(params[0].name, extractor.PARAM_ORIGINATOR(), "param 0 name");
        assertEq(abi.decode(params[0].value, (address)), originator, "param 0 value");

        assertEq(params[1].name, extractor.PARAM_SHARES_AMOUNT(), "param 1 name");
        assertEq(abi.decode(params[1].value, (uint256)), sharesAmount, "param 1 value");

        assertEq(params[2].name, extractor.PARAM_ASSET_AMOUNT(), "param 2 name");
        assertEq(abi.decode(params[2].value, (uint256)), assetAmount, "param 2 value");
    }

    function test_extract_fail_unsupportedSelector() public {
        bytes4 badSelector = bytes4(keccak256("notPostDeposit()"));

        __test_extract_fail_unsupportedSelector(badSelector);
    }

    function test_extract_fail_unsupportedSelector_postExecuteDepositRequest() public {
        // The sibling post-issuance selectors share the calldata shape but have their own extractors.
        __test_extract_fail_unsupportedSelector(
            IERC7540LikeDepositQueuePostExecuteDepositRequestHook.postExecuteDepositRequest.selector
        );
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
            data: abi.encode(originator, sharesAmount, assetAmount),
            context: bytes("")
        });

        vm.expectRevert(abi.encodeWithSelector(IPolicyEngine.UnsupportedSelector.selector, _selector));
        extractor.extract(payload);
    }
}
