// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {SharesBurnHandler} from "src/components/issuance/redeem-handlers/SharesBurnHandler.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {ISharesBurnHandlerPreBurnHook} from "src/components/issuance/interfaces/ISharesBurnHandlerPreBurnHook.sol";
import {Shares} from "src/shares/Shares.sol";

import {SharesBurnHandlerHarness} from "test/harnesses/SharesBurnHandlerHarness.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract SharesBurnHandlerTest is TestHelpers {
    Shares shares;
    address owner;
    address admin = makeAddr("admin");
    address randomUser = makeAddr("randomUser");

    SharesBurnHandlerHarness burnHandler;

    address holder1 = makeAddr("holder1");
    address holder2 = makeAddr("holder2");
    uint256 holderBalance = 1000e18;
    uint256 sharesAmount1 = 100e18;
    uint256 sharesAmount2 = 23e18;

    function setUp() public {
        shares = createShares();
        owner = shares.owner();

        vm.prank(owner);
        shares.addAdmin(admin);

        // Deploy harness; registration as a redeem handler is done per test branch
        burnHandler = new SharesBurnHandlerHarness(address(shares));

        // Seed holders with shares
        deal(address(shares), holder1, holderBalance, true);
        deal(address(shares), holder2, holderBalance, true);
    }

    function __burnInputs() internal view returns (SharesBurnHandler.BurnInput[] memory inputs_) {
        inputs_ = new SharesBurnHandler.BurnInput[](2);
        inputs_[0] = SharesBurnHandler.BurnInput({from: holder1, sharesAmount: sharesAmount1});
        inputs_[1] = SharesBurnHandler.BurnInput({from: holder2, sharesAmount: sharesAmount2});
    }

    modifier whenSettingThePre_burnHook() {
        _;
    }

    function test_WhenTheHookSetterIsNotTheAdminOrOwner() external whenSettingThePre_burnHook {
        // It should revert with {ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized}.
        vm.expectRevert(
            ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector, address(burnHandler)
        );
        vm.prank(randomUser);
        burnHandler.setPreBurnHook(makeAddr("preBurnHook"));
    }

    function test_WhenTheHookSetterIsTheAdminOrOwner() external whenSettingThePre_burnHook {
        address hook = makeAddr("preBurnHook");

        // It should emit {PreBurnHookSet}.
        vm.expectEmit(address(burnHandler));
        emit SharesBurnHandler.PreBurnHookSet(hook);

        vm.prank(admin);
        burnHandler.setPreBurnHook(hook);

        // It should store the pre-burn hook.
        assertEq(burnHandler.getPreBurnHook(), hook, "hook not stored");
    }

    modifier whenBurningShares() {
        _;
    }

    function test_WhenTheBurnCallerIsNotTheAdminOrOwner() external whenBurningShares {
        // It should revert with {ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized}.
        vm.expectRevert(
            ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector, address(burnHandler)
        );
        vm.prank(randomUser);
        burnHandler.burn(__burnInputs());
    }

    modifier whenTheBurnCallerIsTheAdminOrOwner() {
        _;
    }

    function test_GivenTheHandlerIsNotRegisteredAsARedeemHandler()
        external
        whenBurningShares
        whenTheBurnCallerIsTheAdminOrOwner
    {
        // All inputs are non-zero so the per-input zero check passes and `burnFor` reaches the
        // registration gate inside Shares, deterministically hitting the unauthorized revert.
        // It should revert with {Shares__OnlyRedeemHandler__Unauthorized}.
        vm.expectRevert(Shares.Shares__OnlyRedeemHandler__Unauthorized.selector, address(shares));
        vm.prank(admin);
        burnHandler.burn(__burnInputs());
    }

    modifier givenTheHandlerIsRegisteredAsARedeemHandler() {
        vm.prank(admin);
        shares.addRedeemHandler(address(burnHandler));
        _;
    }

    function test_WhenAnyInputHasAZeroSharesAmount()
        external
        whenBurningShares
        whenTheBurnCallerIsTheAdminOrOwner
        givenTheHandlerIsRegisteredAsARedeemHandler
    {
        // It should revert with {SharesBurnHandler__Burn__ZeroShares}.
        // "Any input" is proven at both boundary positions: a zero at the last and at the first index.
        SharesBurnHandler.BurnInput[] memory inputs = __burnInputs();
        inputs[1].sharesAmount = 0;
        vm.expectRevert(SharesBurnHandler.SharesBurnHandler__Burn__ZeroShares.selector, address(burnHandler));
        vm.prank(admin);
        burnHandler.burn(inputs);

        inputs = __burnInputs();
        inputs[0].sharesAmount = 0;
        vm.expectRevert(SharesBurnHandler.SharesBurnHandler__Burn__ZeroShares.selector, address(burnHandler));
        vm.prank(admin);
        burnHandler.burn(inputs);
    }

    modifier whenAllInputsHaveANon_zeroSharesAmount() {
        _;
    }

    function test_GivenNoPre_burnHookIsSet()
        external
        whenBurningShares
        whenTheBurnCallerIsTheAdminOrOwner
        givenTheHandlerIsRegisteredAsARedeemHandler
        whenAllInputsHaveANon_zeroSharesAmount
    {
        SharesBurnHandler.BurnInput[] memory inputs = __burnInputs();
        uint256 totalSupplyBefore = shares.totalSupply();

        // It should emit {SharesBurned} per input.
        vm.expectEmit(address(burnHandler));
        emit SharesBurnHandler.SharesBurned({caller: admin, from: holder1, sharesAmount: sharesAmount1});
        vm.expectEmit(address(burnHandler));
        emit SharesBurnHandler.SharesBurned({caller: admin, from: holder2, sharesAmount: sharesAmount2});

        vm.prank(admin);
        burnHandler.burn(inputs);

        // It should burn the shares amount from each holder.
        assertEq(shares.balanceOf(holder1), holderBalance - sharesAmount1, "holder1 shares not burned");
        assertEq(shares.balanceOf(holder2), holderBalance - sharesAmount2, "holder2 shares not burned");
        assertEq(shares.totalSupply(), totalSupplyBefore - sharesAmount1 - sharesAmount2, "unexpected total supply");
    }

    function test_GivenAPre_burnHookIsSet()
        external
        whenBurningShares
        whenTheBurnCallerIsTheAdminOrOwner
        givenTheHandlerIsRegisteredAsARedeemHandler
        whenAllInputsHaveANon_zeroSharesAmount
    {
        SharesBurnHandler.BurnInput[] memory inputs = __burnInputs();
        uint256 totalSupplyBefore = shares.totalSupply();

        address hook = makeAddr("preBurnHook");
        vm.prank(admin);
        burnHandler.setPreBurnHook(hook);

        bytes memory expectedCall1 =
            abi.encodeCall(ISharesBurnHandlerPreBurnHook.preBurn, (admin, holder1, sharesAmount1));
        bytes memory expectedCall2 =
            abi.encodeCall(ISharesBurnHandlerPreBurnHook.preBurn, (admin, holder2, sharesAmount2));
        vm.mockCall(hook, expectedCall1, bytes(""));
        vm.mockCall(hook, expectedCall2, bytes(""));

        // It should call the pre-burn hook per input with the caller, holder, and shares amount.
        vm.expectCall(hook, expectedCall1);
        vm.expectCall(hook, expectedCall2);

        // It should emit {SharesBurned} per input.
        vm.expectEmit(address(burnHandler));
        emit SharesBurnHandler.SharesBurned({caller: admin, from: holder1, sharesAmount: sharesAmount1});
        vm.expectEmit(address(burnHandler));
        emit SharesBurnHandler.SharesBurned({caller: admin, from: holder2, sharesAmount: sharesAmount2});

        vm.prank(admin);
        burnHandler.burn(inputs);

        // It should burn the shares amount from each holder.
        assertEq(shares.balanceOf(holder1), holderBalance - sharesAmount1, "holder1 shares not burned");
        assertEq(shares.balanceOf(holder2), holderBalance - sharesAmount2, "holder2 shares not burned");
        assertEq(shares.totalSupply(), totalSupplyBefore - sharesAmount1 - sharesAmount2, "unexpected total supply");
    }
}
