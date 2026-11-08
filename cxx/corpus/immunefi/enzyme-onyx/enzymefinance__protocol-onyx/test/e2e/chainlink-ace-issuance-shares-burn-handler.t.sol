// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IntervalPolicy} from "@chainlink/policy-management/policies/IntervalPolicy.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

import {
    ChainlinkAceSharesBurnHandlerPreBurnValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceSharesBurnHandlerPreBurnValidator.sol";
import {ISharesBurnHandlerPreBurnHook} from "src/components/issuance/interfaces/ISharesBurnHandlerPreBurnHook.sol";
import {SharesBurnHandler} from "src/components/issuance/redeem-handlers/SharesBurnHandler.sol";

import {SharesBurnHandlerHarness} from "test/harnesses/SharesBurnHandlerHarness.sol";
import {ChainlinkAceIssuanceE2ETestBase} from "test/utils/ChainlinkAceIssuanceE2ETestBase.sol";

/// @dev Proves the full preBurn flow: SharesBurnHandler ->
/// ChainlinkAceSharesBurnHandlerPreBurnValidator -> engine -> IntervalPolicy.
/// IntervalPolicy reads only `block.timestamp`, so no extractor is registered: the engine's
/// `_extractParameters` returns empty when none is set, and `addPolicy` gets an empty param list.
/// The preBurn extractor remains covered by its unit tests (`test/contracts/ChainlinkAce*Extractor.t.sol`).
contract ChainlinkAceIssuanceSharesBurnHandlerE2ETest is ChainlinkAceIssuanceE2ETestBase {
    address burnHolder = makeAddr("burnHolder");

    SharesBurnHandlerHarness sharesBurnHandler;
    ChainlinkAceSharesBurnHandlerPreBurnValidator preBurnValidator;

    // Daily cycle of 24 one-hour slots; burns allowed only within [09:00, 17:00) UTC.
    uint256 constant SLOT_DURATION = 1 hours;
    uint256 constant CYCLE_SIZE = 24;
    uint256 constant START_SLOT = 9;
    uint256 constant END_SLOT = 17;

    function setUp() public override {
        super.setUp();

        sharesBurnHandler = new SharesBurnHandlerHarness(address(shares));
        vm.prank(admin);
        shares.addRedeemHandler(address(sharesBurnHandler));

        // Seed the burn holder with shares for the forced-burn flow.
        deal(address(shares), burnHolder, 1000e18, true);

        // Engine must exist before the validator: `init` attaches to it.
        preBurnValidator = ChainlinkAceSharesBurnHandlerPreBurnValidator(
            deployChainlinkAceSharesBurnHandlerPreBurnValidator(address(shares), address(sharesBurnHandler), engine)
        );
        vm.prank(admin);
        sharesBurnHandler.setPreBurnHook(address(preBurnValidator));

        address intervalPolicy = __deployPolicy(
            address(new IntervalPolicy()),
            abi.encode(
                START_SLOT,
                END_SLOT,
                IntervalPolicy.CycleParameters({slotDuration: SLOT_DURATION, cycleSize: CYCLE_SIZE, cycleOffset: 0})
            )
        );

        vm.prank(engineOwner);
        IPolicyEngine(engine)
            .addPolicy(
                address(preBurnValidator),
                ISharesBurnHandlerPreBurnHook.preBurn.selector,
                intervalPolicy,
                new bytes32[](0)
            );

        // Start inside the allowed window (12:00).
        vm.warp(12 hours);
    }

    function test_burn_succeeds_whenInsideInterval() public {
        uint256 sharesAmount = 100e18;
        uint256 balanceBefore = shares.balanceOf(burnHolder);

        SharesBurnHandler.BurnInput[] memory inputs = new SharesBurnHandler.BurnInput[](1);
        inputs[0] = SharesBurnHandler.BurnInput({from: burnHolder, sharesAmount: sharesAmount});

        vm.prank(admin);
        sharesBurnHandler.burn(inputs);

        assertEq(shares.balanceOf(burnHolder), balanceBefore - sharesAmount, "shares not burned");
    }

    function test_burn_reverts_whenOutsideInterval() public {
        // 20:00 falls outside the [09:00, 17:00) window.
        vm.warp(20 hours);

        SharesBurnHandler.BurnInput[] memory inputs = new SharesBurnHandler.BurnInput[](1);
        inputs[0] = SharesBurnHandler.BurnInput({from: burnHolder, sharesAmount: 100e18});

        vm.expectPartialRevert(IPolicyEngine.PolicyRunRejected.selector);
        vm.prank(admin);
        sharesBurnHandler.burn(inputs);
    }
}
