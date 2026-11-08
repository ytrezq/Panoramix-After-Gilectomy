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
    ChainlinkAceSyncRedeemHandlerPostRedeemValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceSyncRedeemHandlerPostRedeemValidator.sol";
import {
    ChainlinkAceSyncRedeemHandlerPostRedeemExtractor
} from "src/components/issuance/hooks/chainlink-ace/extractors/ChainlinkAceSyncRedeemHandlerPostRedeemExtractor.sol";
import {
    ISyncRedeemHandlerPostRedeemHook
} from "src/components/issuance/interfaces/ISyncRedeemHandlerPostRedeemHook.sol";

import {SyncRedeemHandlerHarness} from "test/harnesses/SyncRedeemHandlerHarness.sol";
import {ChainlinkAceIssuanceE2ETestBase} from "test/utils/ChainlinkAceIssuanceE2ETestBase.sol";

/// @dev Proves the full postRedeem flow: SyncRedeemHandler ->
/// ChainlinkAceSyncRedeemHandlerPostRedeemValidator -> engine -> extractor + VolumePolicy on `assetAmount`.
contract ChainlinkAceIssuanceSyncRedeemHandlerE2ETest is ChainlinkAceIssuanceE2ETestBase {
    address redeemer = makeAddr("redeemer");

    SyncRedeemHandlerHarness syncRedeemHandler;
    ChainlinkAceSyncRedeemHandlerPostRedeemValidator postRedeemValidator;

    // VolumePolicy operates on the raw asset amount paid out (6 decimals).
    uint256 constant MAX_ASSET_AMOUNT = 100e6;

    function setUp() public override {
        super.setUp();

        syncRedeemHandler = new SyncRedeemHandlerHarness(address(shares));
        syncRedeemHandler.init(depositAsset);
        vm.prank(admin);
        shares.addRedeemHandler(address(syncRedeemHandler));

        deal(address(shares), redeemer, 1000e18, true);

        // Seed Shares with the asset so redemptions can be paid out.
        deal(depositAsset, address(shares), 1000e6, true);

        // Engine must exist before the validator: `init` attaches to it.
        postRedeemValidator = ChainlinkAceSyncRedeemHandlerPostRedeemValidator(
            deployChainlinkAceSyncRedeemHandlerPostRedeemValidator(address(shares), address(syncRedeemHandler), engine)
        );
        vm.prank(admin);
        syncRedeemHandler.setPostRedeemHook(address(postRedeemValidator));

        ChainlinkAceSyncRedeemHandlerPostRedeemExtractor extractor =
            new ChainlinkAceSyncRedeemHandlerPostRedeemExtractor();

        bytes32[] memory params = new bytes32[](1);
        params[0] = extractor.PARAM_ASSET_AMOUNT();

        vm.startPrank(engineOwner);
        IPolicyEngine(engine).setExtractor(ISyncRedeemHandlerPostRedeemHook.postRedeem.selector, address(extractor));
        IPolicyEngine(engine)
            .addPolicy(
                address(postRedeemValidator),
                ISyncRedeemHandlerPostRedeemHook.postRedeem.selector,
                __deployPolicy(address(new VolumePolicy()), abi.encode(uint256(0), MAX_ASSET_AMOUNT)),
                params
            );
        vm.stopPrank();
    }

    function test_redeem_succeeds_whenAmountWithinLimit() public {
        uint256 sharesAmount = 250e18; // pays 50e6 assets, <= MAX_ASSET_AMOUNT
        uint256 sharesBefore = shares.balanceOf(redeemer);
        uint256 assetsBefore = IERC20(depositAsset).balanceOf(redeemer);

        vm.prank(redeemer);
        uint256 assetsReceived = syncRedeemHandler.redeem({_sharesAmount: sharesAmount});

        assertEq(assetsReceived, 50e6, "incorrect assets paid");
        assertEq(IERC20(depositAsset).balanceOf(redeemer), assetsBefore + assetsReceived, "incorrect asset balance");
        assertEq(shares.balanceOf(redeemer), sharesBefore - sharesAmount, "incorrect shares balance");
    }

    function test_redeem_reverts_whenAmountExceedsLimit() public {
        uint256 sharesAmount = 750e18; // pays 150e6 assets, > MAX_ASSET_AMOUNT

        // Reverts via the engine's PolicyRunRejected wrapper, proving the extractor's `assetAmount`
        // parameter is what VolumePolicy rejects on (the success case differs only in amount).
        vm.expectPartialRevert(IPolicyEngine.PolicyRunRejected.selector);
        vm.prank(redeemer);
        syncRedeemHandler.redeem({_sharesAmount: sharesAmount});
    }
}
