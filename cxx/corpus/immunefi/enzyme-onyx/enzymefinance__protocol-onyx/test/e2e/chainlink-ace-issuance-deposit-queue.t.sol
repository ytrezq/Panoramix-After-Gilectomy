// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {MaxPolicy} from "@chainlink/policy-management/policies/MaxPolicy.sol";
import {VolumeRatePolicy} from "@chainlink/policy-management/policies/VolumeRatePolicy.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

import {
    ChainlinkAceERC7540LikeDepositQueuePreRequestDepositValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceERC7540LikeDepositQueuePreRequestDepositValidator.sol";
import {
    ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestValidator.sol";
import {
    ChainlinkAceERC7540LikeDepositQueuePreRequestDepositExtractor
} from "src/components/issuance/hooks/chainlink-ace/extractors/ChainlinkAceERC7540LikeDepositQueuePreRequestDepositExtractor.sol";
import {
    ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestExtractor
} from "src/components/issuance/hooks/chainlink-ace/extractors/ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestExtractor.sol";
import {
    IERC7540LikeDepositQueuePreRequestDepositHook
} from "src/components/issuance/interfaces/IERC7540LikeDepositQueuePreRequestDepositHook.sol";
import {
    IERC7540LikeDepositQueuePostExecuteDepositRequestHook
} from "src/components/issuance/interfaces/IERC7540LikeDepositQueuePostExecuteDepositRequestHook.sol";

import {ERC7540LikeDepositQueueHarness} from "test/harnesses/ERC7540LikeDepositQueueHarness.sol";
import {ChainlinkAceIssuanceE2ETestBase} from "test/utils/ChainlinkAceIssuanceE2ETestBase.sol";

/// @dev Proves the full deposit queue flows: ERC7540LikeDepositQueue ->
/// - preRequestDeposit: ChainlinkAceERC7540LikeDepositQueuePreRequestDepositValidator -> engine ->
///   extractor + MaxPolicy on `assetAmount`
/// - postExecuteDepositRequest: ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestValidator ->
///   engine -> extractor + VolumeRatePolicy on `[assetAmount, controller]` (per-period cumulative volume,
///   accumulated via the engine-driven `postRun`)
contract ChainlinkAceIssuanceDepositQueueE2ETest is ChainlinkAceIssuanceE2ETestBase {
    address depositor = makeAddr("depositor");

    ERC7540LikeDepositQueueHarness depositQueue;
    ChainlinkAceERC7540LikeDepositQueuePreRequestDepositValidator preRequestDepositValidator;
    ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestValidator postExecuteDepositRequestValidator;

    // MaxPolicy gates each request amount independently (no accumulation between calls).
    uint256 constant MAX_REQUEST_ASSET_AMOUNT = 200e6;
    // VolumeRatePolicy caps the controller's cumulative executed volume within a time period,
    // so two executions that each pass MaxPolicy can together exceed the period cap.
    uint256 constant TIME_PERIOD_DURATION = 1 days;
    uint256 constant MAX_PERIOD_ASSET_AMOUNT = 150e6;

    function setUp() public override {
        super.setUp();

        depositQueue = new ERC7540LikeDepositQueueHarness(address(shares));
        vm.prank(admin);
        shares.addDepositHandler(address(depositQueue));
        vm.prank(admin);
        depositQueue.setAsset(depositAsset);

        deal(depositAsset, depositor, 1000e6, true);
        vm.prank(depositor);
        IERC20(depositAsset).approve(address(depositQueue), type(uint256).max);

        // Engine must exist before the validators: `init` attaches to it.
        preRequestDepositValidator = ChainlinkAceERC7540LikeDepositQueuePreRequestDepositValidator(
            deployChainlinkAceERC7540LikeDepositQueuePreRequestDepositValidator(
                address(shares), address(depositQueue), engine
            )
        );
        postExecuteDepositRequestValidator = ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestValidator(
            deployChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestValidator(
                    address(shares), address(depositQueue), engine
                )
        );

        vm.startPrank(admin);
        depositQueue.setPreRequestDepositHook(address(preRequestDepositValidator));
        depositQueue.setPostExecuteDepositRequestHook(address(postExecuteDepositRequestValidator));
        vm.stopPrank();

        ChainlinkAceERC7540LikeDepositQueuePreRequestDepositExtractor preRequestDepositExtractor =
            new ChainlinkAceERC7540LikeDepositQueuePreRequestDepositExtractor();
        ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestExtractor postExecuteDepositRequestExtractor =
            new ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestExtractor();

        bytes32[] memory preRequestParams = new bytes32[](1);
        preRequestParams[0] = preRequestDepositExtractor.PARAM_ASSET_AMOUNT();

        // VolumeRatePolicy expects `[amount, account]`: track the executed asset amount per controller.
        bytes32[] memory postExecuteParams = new bytes32[](2);
        postExecuteParams[0] = postExecuteDepositRequestExtractor.PARAM_ASSET_AMOUNT();
        postExecuteParams[1] = postExecuteDepositRequestExtractor.PARAM_CONTROLLER();

        vm.startPrank(engineOwner);
        IPolicyEngine(engine)
            .setExtractor(
                IERC7540LikeDepositQueuePreRequestDepositHook.preRequestDeposit.selector,
                address(preRequestDepositExtractor)
            );
        IPolicyEngine(engine)
            .setExtractor(
                IERC7540LikeDepositQueuePostExecuteDepositRequestHook.postExecuteDepositRequest.selector,
                address(postExecuteDepositRequestExtractor)
            );
        IPolicyEngine(engine)
            .addPolicy(
                address(preRequestDepositValidator),
                IERC7540LikeDepositQueuePreRequestDepositHook.preRequestDeposit.selector,
                __deployPolicy(address(new MaxPolicy()), abi.encode(MAX_REQUEST_ASSET_AMOUNT)),
                preRequestParams
            );
        IPolicyEngine(engine)
            .addPolicy(
                address(postExecuteDepositRequestValidator),
                IERC7540LikeDepositQueuePostExecuteDepositRequestHook.postExecuteDepositRequest.selector,
                __deployPolicy(
                    address(new VolumeRatePolicy()), abi.encode(TIME_PERIOD_DURATION, MAX_PERIOD_ASSET_AMOUNT)
                ),
                postExecuteParams
            );
        vm.stopPrank();
    }

    function __executeDepositRequest(uint256 _requestId) private {
        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = _requestId;

        vm.prank(admin);
        depositQueue.executeDepositRequests({_requestIds: requestIds});
    }

    //==================================================================================================================
    // preRequestDeposit: MaxPolicy
    //==================================================================================================================

    function test_requestDeposit_succeeds_whenAmountWithinMax() public {
        uint256 depositAmount = 100e6; // <= MAX_REQUEST_ASSET_AMOUNT

        vm.prank(depositor);
        uint256 requestId =
            depositQueue.requestDeposit({_assets: depositAmount, _controller: depositor, _owner: depositor});

        assertEq(depositQueue.getDepositRequest(requestId).assetAmount, depositAmount, "request not created");
    }

    function test_requestDeposit_reverts_whenAmountExceedsMax() public {
        uint256 depositAmount = 300e6; // > MAX_REQUEST_ASSET_AMOUNT

        vm.expectPartialRevert(IPolicyEngine.PolicyRunRejected.selector);
        vm.prank(depositor);
        depositQueue.requestDeposit({_assets: depositAmount, _controller: depositor, _owner: depositor});
    }

    //==================================================================================================================
    // postExecuteDepositRequest: VolumeRatePolicy
    //==================================================================================================================

    function test_executeDepositRequests_succeeds_whenPeriodVolumeWithinLimit() public {
        uint256 depositAmount = 100e6; // <= MAX_PERIOD_ASSET_AMOUNT

        vm.prank(depositor);
        uint256 requestId =
            depositQueue.requestDeposit({_assets: depositAmount, _controller: depositor, _owner: depositor});

        __executeDepositRequest(requestId);

        assertGt(shares.balanceOf(depositor), 0, "no shares minted");
    }

    function test_executeDepositRequests_reverts_whenPeriodVolumeExceeded() public {
        // Each request passes MaxPolicy, and the first execution fits the period cap, but the
        // second execution in the same period pushes the controller's cumulative volume over it —
        // proving the engine-driven `postRun` accumulation.
        uint256 depositAmount = 100e6; // 2 * depositAmount > MAX_PERIOD_ASSET_AMOUNT

        vm.startPrank(depositor);
        uint256 firstRequestId =
            depositQueue.requestDeposit({_assets: depositAmount, _controller: depositor, _owner: depositor});
        uint256 secondRequestId =
            depositQueue.requestDeposit({_assets: depositAmount, _controller: depositor, _owner: depositor});
        vm.stopPrank();

        __executeDepositRequest(firstRequestId);

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = secondRequestId;

        vm.expectPartialRevert(IPolicyEngine.PolicyRunRejected.selector);
        vm.prank(admin);
        depositQueue.executeDepositRequests({_requestIds: requestIds});
    }
}
