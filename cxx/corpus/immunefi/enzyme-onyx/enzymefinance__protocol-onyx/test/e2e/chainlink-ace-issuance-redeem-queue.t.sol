// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {OnlyAuthorizedSenderPolicy} from "@chainlink/policy-management/policies/OnlyAuthorizedSenderPolicy.sol";
import {PausePolicy} from "@chainlink/policy-management/policies/PausePolicy.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

import {
    ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidator.sol";
import {
    ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidator.sol";
import {
    IERC7540LikeRedeemQueuePreRequestRedeemHook
} from "src/components/issuance/interfaces/IERC7540LikeRedeemQueuePreRequestRedeemHook.sol";
import {
    IERC7540LikeRedeemQueuePostExecuteRedeemRequestHook
} from "src/components/issuance/interfaces/IERC7540LikeRedeemQueuePostExecuteRedeemRequestHook.sol";

import {ERC7540LikeRedeemQueueHarness} from "test/harnesses/ERC7540LikeRedeemQueueHarness.sol";
import {ChainlinkAceIssuanceE2ETestBase} from "test/utils/ChainlinkAceIssuanceE2ETestBase.sol";

/// @dev Proves the full redeem queue flows: ERC7540LikeRedeemQueue ->
/// - preRequestRedeem: ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidator -> engine ->
///   OnlyAuthorizedSenderPolicy
/// - postExecuteRedeemRequest: ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidator ->
///   engine -> PausePolicy
/// Neither policy consumes extracted params, so no extractor is registered: the engine's
/// `_extractParameters` returns empty when none is set, and `addPolicy` gets an empty param list.
/// The redeem extractors remain covered by their unit tests (`test/contracts/ChainlinkAce*Extractor.t.sol`).
contract ChainlinkAceIssuanceRedeemQueueE2ETest is ChainlinkAceIssuanceE2ETestBase {
    address redeemer = makeAddr("redeemer");

    ERC7540LikeRedeemQueueHarness redeemQueue;
    ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidator preRequestRedeemValidator;
    ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidator postExecuteRedeemRequestValidator;

    OnlyAuthorizedSenderPolicy onlyAuthorizedSenderPolicy;
    PausePolicy pausePolicy;

    function setUp() public override {
        super.setUp();

        redeemQueue = new ERC7540LikeRedeemQueueHarness(address(shares));
        vm.prank(admin);
        shares.addRedeemHandler(address(redeemQueue));
        vm.prank(admin);
        redeemQueue.setAsset(depositAsset);

        deal(address(shares), redeemer, 1000e18, true);
        vm.prank(redeemer);
        shares.approve(address(redeemQueue), type(uint256).max);

        // Seed Shares with the asset so redemptions can be paid out.
        deal(depositAsset, address(shares), 1000e6, true);

        // Engine must exist before the validators: `init` attaches to it.
        preRequestRedeemValidator = ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidator(
            deployChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidator(
                address(shares), address(redeemQueue), engine
            )
        );
        postExecuteRedeemRequestValidator = ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidator(
            deployChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidator(
                address(shares), address(redeemQueue), engine
            )
        );

        vm.startPrank(admin);
        redeemQueue.setPreRequestRedeemHook(address(preRequestRedeemValidator));
        redeemQueue.setPostExecuteRedeemRequestHook(address(postExecuteRedeemRequestValidator));
        vm.stopPrank();

        onlyAuthorizedSenderPolicy =
            OnlyAuthorizedSenderPolicy(__deployPolicy(address(new OnlyAuthorizedSenderPolicy()), bytes("")));
        pausePolicy = PausePolicy(__deployPolicy(address(new PausePolicy()), abi.encode(false)));

        // The policy's `caller` is `payload.sender = msg.sender` of the hook call, i.e. the redeem
        // queue contract (not the end user) — authorizing the queue proves that wiring.
        vm.prank(policyOwner);
        onlyAuthorizedSenderPolicy.authorizeSender(address(redeemQueue));

        vm.startPrank(engineOwner);
        IPolicyEngine(engine)
            .addPolicy(
                address(preRequestRedeemValidator),
                IERC7540LikeRedeemQueuePreRequestRedeemHook.preRequestRedeem.selector,
                address(onlyAuthorizedSenderPolicy),
                new bytes32[](0)
            );
        IPolicyEngine(engine)
            .addPolicy(
                address(postExecuteRedeemRequestValidator),
                IERC7540LikeRedeemQueuePostExecuteRedeemRequestHook.postExecuteRedeemRequest.selector,
                address(pausePolicy),
                new bytes32[](0)
            );
        vm.stopPrank();
    }

    //==================================================================================================================
    // preRequestRedeem: OnlyAuthorizedSenderPolicy
    //==================================================================================================================

    function test_requestRedeem_succeeds_whenSenderAuthorized() public {
        uint256 sharesAmount = 100e18;

        vm.prank(redeemer);
        uint256 requestId = redeemQueue.requestRedeem({_shares: sharesAmount, _controller: redeemer, _owner: redeemer});

        assertEq(redeemQueue.getRedeemRequest(requestId).sharesAmount, sharesAmount, "request not created");
    }

    function test_requestRedeem_reverts_whenSenderNotAuthorized() public {
        vm.prank(policyOwner);
        onlyAuthorizedSenderPolicy.unauthorizeSender(address(redeemQueue));

        vm.expectPartialRevert(IPolicyEngine.PolicyRunRejected.selector);
        vm.prank(redeemer);
        redeemQueue.requestRedeem({_shares: 100e18, _controller: redeemer, _owner: redeemer});
    }

    //==================================================================================================================
    // postExecuteRedeemRequest: PausePolicy
    //==================================================================================================================

    function test_executeRedeemRequests_succeeds_whenNotPaused() public {
        uint256 sharesAmount = 100e18;

        vm.prank(redeemer);
        uint256 requestId = redeemQueue.requestRedeem({_shares: sharesAmount, _controller: redeemer, _owner: redeemer});

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId;

        vm.prank(admin);
        redeemQueue.executeRedeemRequests({_requestIds: requestIds});

        assertGt(IERC20(depositAsset).balanceOf(redeemer), 0, "no assets paid out");
    }

    function test_executeRedeemRequests_reverts_whenPaused() public {
        uint256 sharesAmount = 100e18;

        vm.prank(redeemer);
        uint256 requestId = redeemQueue.requestRedeem({_shares: sharesAmount, _controller: redeemer, _owner: redeemer});

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId;

        vm.prank(policyOwner);
        pausePolicy.setPausedState(true);

        vm.expectPartialRevert(IPolicyEngine.PolicyRunRejected.selector);
        vm.prank(admin);
        redeemQueue.executeRedeemRequests({_requestIds: requestIds});
    }
}
