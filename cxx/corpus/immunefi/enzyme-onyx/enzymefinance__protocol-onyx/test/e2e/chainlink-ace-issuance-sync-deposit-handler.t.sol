// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {VolumePolicy} from "@chainlink/policy-management/policies/VolumePolicy.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

import {
    ChainlinkAceSyncDepositHandlerPostDepositValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceSyncDepositHandlerPostDepositValidator.sol";
import {
    ChainlinkAceSyncDepositHandlerPostDepositExtractor
} from "src/components/issuance/hooks/chainlink-ace/extractors/ChainlinkAceSyncDepositHandlerPostDepositExtractor.sol";
import {
    ISyncDepositHandlerPostDepositHook
} from "src/components/issuance/interfaces/ISyncDepositHandlerPostDepositHook.sol";

import {SyncDepositHandlerHarness} from "test/harnesses/SyncDepositHandlerHarness.sol";
import {ChainlinkAceIssuanceE2ETestBase} from "test/utils/ChainlinkAceIssuanceE2ETestBase.sol";

/// @dev Proves the full postDeposit flow: SyncDepositHandler ->
/// ChainlinkAceSyncDepositHandlerPostDepositValidator -> engine -> extractor + VolumePolicy on `assetAmount`.
contract ChainlinkAceIssuanceSyncDepositHandlerE2ETest is ChainlinkAceIssuanceE2ETestBase {
    address depositor = makeAddr("depositor");

    SyncDepositHandlerHarness syncDepositHandler;
    ChainlinkAceSyncDepositHandlerPostDepositValidator postDepositValidator;

    // VolumePolicy operates on the raw asset amount (6 decimals).
    uint256 constant MAX_ASSET_AMOUNT = 200e6;

    function setUp() public override {
        super.setUp();

        syncDepositHandler = new SyncDepositHandlerHarness(address(shares));
        syncDepositHandler.init(depositAsset);
        vm.prank(admin);
        shares.addDepositHandler(address(syncDepositHandler));

        deal(depositAsset, depositor, 1000e6, true);
        vm.prank(depositor);
        IERC20(depositAsset).approve(address(syncDepositHandler), type(uint256).max);

        // Engine must exist before the validator: `init` attaches to it.
        postDepositValidator = ChainlinkAceSyncDepositHandlerPostDepositValidator(
            deployChainlinkAceSyncDepositHandlerPostDepositValidator(
                address(shares), address(syncDepositHandler), engine
            )
        );
        vm.prank(admin);
        syncDepositHandler.setPostDepositHook(address(postDepositValidator));

        ChainlinkAceSyncDepositHandlerPostDepositExtractor extractor =
            new ChainlinkAceSyncDepositHandlerPostDepositExtractor();

        bytes32[] memory params = new bytes32[](1);
        params[0] = extractor.PARAM_ASSET_AMOUNT();

        vm.startPrank(engineOwner);
        IPolicyEngine(engine).setExtractor(ISyncDepositHandlerPostDepositHook.postDeposit.selector, address(extractor));
        IPolicyEngine(engine)
            .addPolicy(
                address(postDepositValidator),
                ISyncDepositHandlerPostDepositHook.postDeposit.selector,
                __deployPolicy(address(new VolumePolicy()), abi.encode(uint256(0), MAX_ASSET_AMOUNT)),
                params
            );
        vm.stopPrank();
    }

    function test_deposit_succeeds_whenAmountWithinLimit() public {
        uint256 depositAmount = 100e6; // <= MAX_ASSET_AMOUNT

        vm.prank(depositor);
        uint256 sharesReceived = syncDepositHandler.deposit({_assetAmount: depositAmount});

        assertGt(sharesReceived, 0, "no shares minted");
        assertEq(shares.balanceOf(depositor), sharesReceived, "incorrect shares balance");
    }

    function test_deposit_reverts_whenAmountExceedsLimit() public {
        uint256 depositAmount = 300e6; // > MAX_ASSET_AMOUNT

        // Reverts via the engine's PolicyRunRejected wrapper, proving the extractor's `assetAmount`
        // parameter is what VolumePolicy rejects on (the success case differs only in amount).
        vm.expectPartialRevert(IPolicyEngine.PolicyRunRejected.selector);
        vm.prank(depositor);
        syncDepositHandler.deposit({_assetAmount: depositAmount});
    }
}
