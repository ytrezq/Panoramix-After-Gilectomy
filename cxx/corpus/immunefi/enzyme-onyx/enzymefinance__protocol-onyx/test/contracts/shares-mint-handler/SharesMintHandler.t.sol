// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {SharesMintHandler} from "src/components/issuance/deposit-handlers/SharesMintHandler.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {ISharesMintHandlerPreMintHook} from "src/components/issuance/interfaces/ISharesMintHandlerPreMintHook.sol";
import {Shares} from "src/shares/Shares.sol";

import {SharesMintHandlerHarness} from "test/harnesses/SharesMintHandlerHarness.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract SharesMintHandlerTest is TestHelpers {
    Shares shares;
    address owner;
    address admin = makeAddr("admin");
    address randomUser = makeAddr("randomUser");

    SharesMintHandlerHarness mintHandler;

    address recipient1 = makeAddr("recipient1");
    address recipient2 = makeAddr("recipient2");
    uint256 sharesAmount1 = 100e18;
    uint256 sharesAmount2 = 23e18;

    function setUp() public {
        shares = createShares();
        owner = shares.owner();

        vm.prank(owner);
        shares.addAdmin(admin);

        // Deploy harness; registration as a deposit handler is done per test branch
        mintHandler = new SharesMintHandlerHarness(address(shares));
    }

    function __mintInputs() internal view returns (SharesMintHandler.MintInput[] memory inputs_) {
        inputs_ = new SharesMintHandler.MintInput[](2);
        inputs_[0] = SharesMintHandler.MintInput({to: recipient1, sharesAmount: sharesAmount1});
        inputs_[1] = SharesMintHandler.MintInput({to: recipient2, sharesAmount: sharesAmount2});
    }

    modifier whenSettingThePre_mintHook() {
        _;
    }

    function test_WhenTheHookSetterIsNotTheAdminOrOwner() external whenSettingThePre_mintHook {
        // It should revert with {ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized}.
        vm.expectRevert(
            ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector, address(mintHandler)
        );
        vm.prank(randomUser);
        mintHandler.setPreMintHook(makeAddr("preMintHook"));
    }

    function test_WhenTheHookSetterIsTheAdminOrOwner() external whenSettingThePre_mintHook {
        address hook = makeAddr("preMintHook");

        // It should emit {PreMintHookSet}.
        vm.expectEmit(address(mintHandler));
        emit SharesMintHandler.PreMintHookSet(hook);

        vm.prank(admin);
        mintHandler.setPreMintHook(hook);

        // It should store the pre-mint hook.
        assertEq(mintHandler.getPreMintHook(), hook, "hook not stored");
    }

    modifier whenMintingShares() {
        _;
    }

    function test_WhenTheMintCallerIsNotTheAdminOrOwner() external whenMintingShares {
        // It should revert with {ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized}.
        vm.expectRevert(
            ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector, address(mintHandler)
        );
        vm.prank(randomUser);
        mintHandler.mint(__mintInputs());
    }

    modifier whenTheMintCallerIsTheAdminOrOwner() {
        _;
    }

    function test_GivenTheHandlerIsNotRegisteredAsADepositHandler()
        external
        whenMintingShares
        whenTheMintCallerIsTheAdminOrOwner
    {
        // All inputs are non-zero so the per-input zero check passes and `mintFor` reaches the
        // registration gate inside Shares, deterministically hitting the unauthorized revert.
        // It should revert with {Shares__OnlyDepositHandler__Unauthorized}.
        vm.expectRevert(Shares.Shares__OnlyDepositHandler__Unauthorized.selector, address(shares));
        vm.prank(admin);
        mintHandler.mint(__mintInputs());
    }

    modifier givenTheHandlerIsRegisteredAsADepositHandler() {
        vm.prank(admin);
        shares.addDepositHandler(address(mintHandler));
        _;
    }

    function test_WhenAnyInputHasAZeroSharesAmount()
        external
        whenMintingShares
        whenTheMintCallerIsTheAdminOrOwner
        givenTheHandlerIsRegisteredAsADepositHandler
    {
        // It should revert with {SharesMintHandler__Mint__ZeroShares}.
        // "Any input" is proven at both boundary positions: a zero at the last and at the first index.
        SharesMintHandler.MintInput[] memory inputs = __mintInputs();
        inputs[1].sharesAmount = 0;
        vm.expectRevert(SharesMintHandler.SharesMintHandler__Mint__ZeroShares.selector, address(mintHandler));
        vm.prank(admin);
        mintHandler.mint(inputs);

        inputs = __mintInputs();
        inputs[0].sharesAmount = 0;
        vm.expectRevert(SharesMintHandler.SharesMintHandler__Mint__ZeroShares.selector, address(mintHandler));
        vm.prank(admin);
        mintHandler.mint(inputs);
    }

    modifier whenAllInputsHaveANon_zeroSharesAmount() {
        _;
    }

    function test_GivenNoPre_mintHookIsSet()
        external
        whenMintingShares
        whenTheMintCallerIsTheAdminOrOwner
        givenTheHandlerIsRegisteredAsADepositHandler
        whenAllInputsHaveANon_zeroSharesAmount
    {
        SharesMintHandler.MintInput[] memory inputs = __mintInputs();

        // It should emit {SharesMinted} per input.
        vm.expectEmit(address(mintHandler));
        emit SharesMintHandler.SharesMinted({caller: admin, to: recipient1, sharesAmount: sharesAmount1});
        vm.expectEmit(address(mintHandler));
        emit SharesMintHandler.SharesMinted({caller: admin, to: recipient2, sharesAmount: sharesAmount2});

        vm.prank(admin);
        mintHandler.mint(inputs);

        // It should mint the shares amount to each recipient.
        assertEq(shares.balanceOf(recipient1), sharesAmount1, "recipient1 shares not minted");
        assertEq(shares.balanceOf(recipient2), sharesAmount2, "recipient2 shares not minted");
        assertEq(shares.totalSupply(), sharesAmount1 + sharesAmount2, "unexpected total supply");
    }

    function test_GivenAPre_mintHookIsSet()
        external
        whenMintingShares
        whenTheMintCallerIsTheAdminOrOwner
        givenTheHandlerIsRegisteredAsADepositHandler
        whenAllInputsHaveANon_zeroSharesAmount
    {
        SharesMintHandler.MintInput[] memory inputs = __mintInputs();

        address hook = makeAddr("preMintHook");
        vm.prank(admin);
        mintHandler.setPreMintHook(hook);

        bytes memory expectedCall1 =
            abi.encodeCall(ISharesMintHandlerPreMintHook.preMint, (admin, recipient1, sharesAmount1));
        bytes memory expectedCall2 =
            abi.encodeCall(ISharesMintHandlerPreMintHook.preMint, (admin, recipient2, sharesAmount2));
        vm.mockCall(hook, expectedCall1, bytes(""));
        vm.mockCall(hook, expectedCall2, bytes(""));

        // It should call the pre-mint hook per input with the caller, recipient, and shares amount.
        vm.expectCall(hook, expectedCall1);
        vm.expectCall(hook, expectedCall2);

        // It should emit {SharesMinted} per input.
        vm.expectEmit(address(mintHandler));
        emit SharesMintHandler.SharesMinted({caller: admin, to: recipient1, sharesAmount: sharesAmount1});
        vm.expectEmit(address(mintHandler));
        emit SharesMintHandler.SharesMinted({caller: admin, to: recipient2, sharesAmount: sharesAmount2});

        vm.prank(admin);
        mintHandler.mint(inputs);

        // It should mint the shares amount to each recipient.
        assertEq(shares.balanceOf(recipient1), sharesAmount1, "recipient1 shares not minted");
        assertEq(shares.balanceOf(recipient2), sharesAmount2, "recipient2 shares not minted");
        assertEq(shares.totalSupply(), sharesAmount1 + sharesAmount2, "unexpected total supply");
    }
}
