// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {TwoWayFeeSplitter} from "../../../src/periphery/auxiliary/TwoWayFeeSplitter.sol";
import {ITwoWayFeeSplitter} from "../../../src/periphery/interface/IFeeSplitter.sol";
import {Clones} from "@openzeppelin-contracts/proxy/Clones.sol";
import {IAccessControl} from "@openzeppelin-contracts/access/IAccessControl.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ConcreteV2RolesLib} from "../../../src/lib/Roles.sol";
import {AccessControl} from "@openzeppelin-contracts/access/AccessControl.sol";
import {ConcreteV2ConstantsLib} from "../../../src/lib/Constants.sol";
import {Math} from "@openzeppelin-contracts/utils/math/Math.sol";

contract MockVault is AccessControl, ERC20 {
    address public immutable vaultManager;

    constructor(address _vaultManager) ERC20("MockVault", "MV") {
        vaultManager = _vaultManager;
        _grantRole(ConcreteV2RolesLib.VAULT_MANAGER, _vaultManager);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract FeeSplitterTest is Test {
    address public feeSplitterImpl;
    TwoWayFeeSplitter public feeSplitter;
    address public alice;
    address public bob;
    address public charlie;
    MockVault public vault;

    function setUp() public {
        feeSplitterImpl = address(new TwoWayFeeSplitter());
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(charlie, "charlie");
        vault = new MockVault(charlie);
        vm.label(address(vault), "mock vault");
        feeSplitter = _initializeFeeSplitter(1, alice);
        vm.label(address(feeSplitter), "fee splitter");
    }

    function test_setFeeSplit() public {
        // prank alice
        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit ITwoWayFeeSplitter.FeeFractionSet(address(vault), 5000);
        vm.expectEmit(true, true, true, true);
        emit ITwoWayFeeSplitter.MainRecipientSet(address(vault), alice);
        vm.expectEmit(true, true, true, true);
        emit ITwoWayFeeSplitter.SecondaryRecipientSet(address(vault), bob);
        feeSplitter.setFeeSplit(address(vault), 5000, alice, bob);
        emit ITwoWayFeeSplitter.RegisterNewFeeSplit(address(vault), 5000, alice, bob);
        vm.stopPrank();
        // check that the fee split is set
        address mainRecipient = feeSplitter.getMainRecipient(address(vault));
        assertEq(mainRecipient, alice);
        address secondaryRecipient = feeSplitter.getSecondaryRecipient(address(vault));
        assertEq(secondaryRecipient, bob);
        uint32 feeFraction = feeSplitter.getFeeFractionForSecondaryRecipient(address(vault));
        assertEq(feeFraction, 5000);
        bool feeSplitForVaultIsActive = feeSplitter.feeSplitForVaultIsActive(address(vault));
        assertEq(feeSplitForVaultIsActive, true);
        bool hasValidFeeSplit = feeSplitter.hasValidFeeSplit(address(vault));
        assertEq(hasValidFeeSplit, true);
    }

    function test_fail_setFeeSplit_InvalidFeeSplit() public {
        ITwoWayFeeSplitter.TwoWayFeeSplit memory invalidFeeSplit1 =
            ITwoWayFeeSplitter.TwoWayFeeSplit(1, alice, address(0), false);
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITwoWayFeeSplitter.InvalidFeeSplit.selector,
                invalidFeeSplit1.feeFractionOfSecondaryRecipient,
                invalidFeeSplit1.mainRecipient,
                invalidFeeSplit1.secondaryRecipient
            )
        );
        feeSplitter.setFeeSplit(
            address(vault),
            invalidFeeSplit1.feeFractionOfSecondaryRecipient,
            invalidFeeSplit1.mainRecipient,
            invalidFeeSplit1.secondaryRecipient
        );
        vm.stopPrank();

        ITwoWayFeeSplitter.TwoWayFeeSplit memory invalidFeeSplit2 =
            ITwoWayFeeSplitter.TwoWayFeeSplit(1, address(0), bob, false);
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITwoWayFeeSplitter.InvalidFeeSplit.selector,
                invalidFeeSplit2.feeFractionOfSecondaryRecipient,
                invalidFeeSplit2.mainRecipient,
                invalidFeeSplit2.secondaryRecipient
            )
        );
        feeSplitter.setFeeSplit(
            address(vault),
            invalidFeeSplit2.feeFractionOfSecondaryRecipient,
            invalidFeeSplit2.mainRecipient,
            invalidFeeSplit2.secondaryRecipient
        );
        vm.stopPrank();
    }

    function test_setFeeSplit_withOneEmptyRecipient() public {
        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit ITwoWayFeeSplitter.MainRecipientSet(address(vault), alice);
        feeSplitter.setFeeSplit(address(vault), 0, alice, address(0));
        vm.stopPrank();
        // check that the fee split is set
        address mainRecipient = feeSplitter.getMainRecipient(address(vault));
        assertEq(mainRecipient, alice, "main recipient should be alice");
        address secondaryRecipient = feeSplitter.getSecondaryRecipient(address(vault));
        assertEq(secondaryRecipient, address(0), "secondary recipient should be address(0)");
    }

    function test_fail_setFeeSplit_feeFractionOutOfBounds() public {
        vm.startPrank(alice);
        vm.expectRevert(ITwoWayFeeSplitter.FeeFractionOutOfBounds.selector);
        feeSplitter.setFeeSplit(address(vault), 10001, alice, bob);
        vm.stopPrank();
    }

    function test_fail_setFeeSplit_Unauthorized() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, bob));
        feeSplitter.setFeeSplit(address(vault), 5000, alice, bob);
        vm.stopPrank();
    }

    function test_distributeFees() public {
        uint256 initialBalance = 1_000_000;
        uint256 feeFraction = 4_000;
        uint256 expectedFeeForBob = initialBalance * feeFraction / 10000;
        uint256 expectedFeeForAlice = initialBalance - expectedFeeForBob;
        // set fee split
        vm.startPrank(alice);
        feeSplitter.setFeeSplit(address(vault), uint32(feeFraction), alice, bob);

        // mint 1000000 tokens to vault
        vault.mint(address(feeSplitter), initialBalance);

        // prank charlie
        vm.expectEmit(true, true, true, true);
        emit ITwoWayFeeSplitter.FeesDistributed(address(vault), expectedFeeForAlice, expectedFeeForBob, alice, bob);
        feeSplitter.distributeFees(address(vault));
        vm.stopPrank();

        // check that the balances are correct
        assertEq(vault.balanceOf(alice), expectedFeeForAlice, "alice balance should be the expected fee for alice");
        assertEq(vault.balanceOf(bob), expectedFeeForBob, "bob balance should be the expected fee for bob");
        assertEq(
            vault.balanceOf(address(feeSplitter)),
            initialBalance - expectedFeeForAlice - expectedFeeForBob,
            "fee splitter balance should be the initial balance minus the fees for alice and bob"
        );
    }

    function test_distributeFees_afterFeeSplitIsSet(uint256 initialBalance, uint32 feeFraction) public {
        // assume the initial balance is greater than 0
        vm.assume(initialBalance > 0);
        // assume that the fee fraction is less than BASIS_POINTS_DENOMINATOR
        vm.assume(feeFraction <= ConcreteV2ConstantsLib.BASIS_POINTS_DENOMINATOR);
        // set fee split
        vm.startPrank(alice);
        feeSplitter.setFeeSplit(address(vault), feeFraction, alice, bob);
        // mint 1000000 tokens to vault
        vault.mint(address(feeSplitter), initialBalance);

        uint256 expectedFeeForBob = Math.mulDiv(
            initialBalance, feeFraction, ConcreteV2ConstantsLib.BASIS_POINTS_DENOMINATOR, Math.Rounding.Floor
        );
        uint256 expectedFeeForAlice = initialBalance - expectedFeeForBob;

        vm.expectEmit(true, true, true, true);
        emit ITwoWayFeeSplitter.FeesDistributed(address(vault), expectedFeeForAlice, expectedFeeForBob, alice, bob);
        feeSplitter.setFeeSplit(address(vault), 5000, alice, charlie);
        vm.stopPrank();
        // // check that 40 percent are at bob and 60 percent are at alice
        assertEq(vault.balanceOf(alice), expectedFeeForAlice, "alice balance should be the expected fee for alice");
        assertEq(vault.balanceOf(bob), expectedFeeForBob, "bob balance should be the expected fee for bob");
        assertEq(
            vault.balanceOf(address(feeSplitter)),
            initialBalance - expectedFeeForAlice - expectedFeeForBob,
            "fee splitter balance should be the initial balance minus the fees for alice and bob"
        );
    }

    function test_distributeFees_afterFeeFractionIsSet(uint256 initialBalance, uint32 feeFraction) public {
        // assume the initial balance is greater than 0
        vm.assume(initialBalance > 0);
        // assume that the fee fraction is less than BASIS_POINTS_DENOMINATOR
        vm.assume(feeFraction <= ConcreteV2ConstantsLib.BASIS_POINTS_DENOMINATOR);
        // set fee split
        vm.startPrank(alice);
        feeSplitter.setFeeSplit(address(vault), feeFraction, alice, bob);
        // mint 1000000 tokens to vault
        vault.mint(address(feeSplitter), initialBalance);
        uint256 expectedFeeForBob = Math.mulDiv(
            initialBalance, feeFraction, ConcreteV2ConstantsLib.BASIS_POINTS_DENOMINATOR, Math.Rounding.Floor
        );
        uint256 expectedFeeForAlice = initialBalance - expectedFeeForBob;
        // prank charlie
        vm.expectEmit(true, true, true, true);
        emit ITwoWayFeeSplitter.FeesDistributed(address(vault), expectedFeeForAlice, expectedFeeForBob, alice, bob);
        feeSplitter.setFeeFraction(address(vault), 5000);
        vm.stopPrank();
        // check that 40 percent are at bob and 60 percent are at alice
        assertEq(vault.balanceOf(alice), expectedFeeForAlice, "alice balance should be the expected fee for alice");
        assertEq(vault.balanceOf(bob), expectedFeeForBob, "bob balance should be the expected fee for bob");
        assertEq(
            vault.balanceOf(address(feeSplitter)),
            initialBalance - expectedFeeForAlice - expectedFeeForBob,
            "fee splitter balance should be the initial balance minus the fees for alice and bob"
        );
    }

    function test_distributeFees_afterMainRecipientIsSet(
        uint256 initialBalance,
        address newMainRecipient,
        uint32 feeFraction
    ) public {
        // set fee split
        // assume the initial balance is greater than 0
        vm.assume(initialBalance > 0 && initialBalance < 10 ** 18);
        // assume that the fee fraction is less than BASIS_POINTS_DENOMINATOR
        vm.assume(feeFraction <= ConcreteV2ConstantsLib.BASIS_POINTS_DENOMINATOR);
        // assume that the new main recipient is not the same as the old main recipient
        vm.assume(newMainRecipient != address(0) && newMainRecipient != address(feeSplitter) && newMainRecipient != bob);
        // set fee split
        vm.startPrank(alice);
        feeSplitter.setFeeSplit(address(vault), feeFraction, alice, bob);
        // mint 1000000 tokens to vault
        vault.mint(address(feeSplitter), initialBalance);
        uint256 expectedFeeForBob = Math.mulDiv(
            initialBalance, feeFraction, ConcreteV2ConstantsLib.BASIS_POINTS_DENOMINATOR, Math.Rounding.Floor
        );
        uint256 expectedFeeForAlice = initialBalance - expectedFeeForBob;
        // prank charlie
        vm.expectEmit(true, true, true, true);
        emit ITwoWayFeeSplitter.FeesDistributed(address(vault), expectedFeeForAlice, expectedFeeForBob, alice, bob);
        feeSplitter.setMainRecipient(address(vault), newMainRecipient);
        vm.stopPrank();
        // check that 40 percent are at bob and 60 percent are at alice
        assertEq(vault.balanceOf(alice), expectedFeeForAlice, "alice balance should be the expected fee for alice");
        assertEq(vault.balanceOf(bob), expectedFeeForBob, "bob balance should be the expected fee for bob");
        assertEq(
            vault.balanceOf(address(feeSplitter)),
            initialBalance - expectedFeeForAlice - expectedFeeForBob,
            "fee splitter balance should be the initial balance minus the fees for alice and bob"
        );
    }

    function test_distributeFees_afterSecondaryRecipientIsSet(
        uint256 initialBalance,
        address newSecondaryRecipient,
        uint32 feeFraction
    ) public {
        // set fee split
        // assume the initial balance is greater than 0
        vm.assume(initialBalance > 0);
        // assume that the fee fraction is less than BASIS_POINTS_DENOMINATOR
        vm.assume(feeFraction <= ConcreteV2ConstantsLib.BASIS_POINTS_DENOMINATOR);
        // assume that the new secondary recipient is not the same as the old secondary recipient
        vm.assume(newSecondaryRecipient != address(0));
        vm.assume(newSecondaryRecipient != address(feeSplitter));
        vm.assume(newSecondaryRecipient != address(alice));
        // set fee split
        vm.startPrank(alice);
        feeSplitter.setFeeSplit(address(vault), feeFraction, alice, bob);
        // mint 1000000 tokens to vault
        vault.mint(address(feeSplitter), initialBalance);
        uint256 expectedFeeForBob = Math.mulDiv(
            initialBalance, feeFraction, ConcreteV2ConstantsLib.BASIS_POINTS_DENOMINATOR, Math.Rounding.Floor
        );
        uint256 expectedFeeForAlice = initialBalance - expectedFeeForBob;
        // prank charlie
        vm.expectEmit(true, true, true, true);
        emit ITwoWayFeeSplitter.FeesDistributed(address(vault), expectedFeeForAlice, expectedFeeForBob, alice, bob);
        feeSplitter.setSecondaryRecipient(address(vault), newSecondaryRecipient);
        vm.stopPrank();
        // check that 40 percent are at bob and 60 percent are at alice
        assertEq(vault.balanceOf(alice), expectedFeeForAlice, "alice balance should be the expected fee for alice");
        assertEq(vault.balanceOf(bob), expectedFeeForBob, "bob balance should be the expected fee for bob");
        assertEq(
            vault.balanceOf(address(feeSplitter)),
            initialBalance - expectedFeeForAlice - expectedFeeForBob,
            "fee splitter balance should be the initial balance minus the fees for alice and bob"
        );
    }

    function test_fail_distributeFees_VaultInvalidOrWIthInvalidFeeSplit() public {
        vm.expectRevert(
            abi.encodeWithSelector(ITwoWayFeeSplitter.VaultInvalidOrWIthInvalidFeeSplit.selector, address(vault))
        );
        feeSplitter.distributeFees(address(vault));
    }

    function test_setMainRecipient_WithoutPreviousFeeSplitBeingSet() public {
        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit ITwoWayFeeSplitter.MainRecipientSet(address(vault), bob);
        feeSplitter.setMainRecipient(address(vault), bob);
        vm.stopPrank();
        // call getMainRecipient
        address mainRecipient = feeSplitter.getMainRecipient(address(vault));
        assertEq(mainRecipient, bob, "main recipient should be bob");
    }

    function test_setMainRecipient_WithPreviousFeeSplitBeingSet() public {
        vm.startPrank(alice);
        feeSplitter.setFeeSplit(address(vault), 5000, alice, bob);
        vm.expectEmit(true, true, true, true);
        emit ITwoWayFeeSplitter.MainRecipientSet(address(vault), charlie);
        feeSplitter.setMainRecipient(address(vault), charlie);
        vm.stopPrank();

        // call getMainRecipient
        address mainRecipient = feeSplitter.getMainRecipient(address(vault));
        assertEq(mainRecipient, charlie, "main recipient should be charlie");
    }

    function test_setMainRecipient_VaultManagerCalls() public {
        // first set the fee split
        vm.startPrank(alice);
        feeSplitter.setFeeSplit(address(vault), 5000, alice, bob);
        vm.stopPrank();
        // prank charlie
        vm.startPrank(charlie);
        vm.expectEmit(true, true, true, true);
        emit ITwoWayFeeSplitter.MainRecipientSet(address(vault), charlie);
        feeSplitter.setMainRecipient(address(vault), charlie);
        vm.stopPrank();
        // call getMainRecipient
        address mainRecipient = feeSplitter.getMainRecipient(address(vault));
        assertEq(mainRecipient, charlie, "main recipient should be charlie");
    }

    function test_fail_setMainRecipient_NeitherOwnerNorVaultManager(address caller) public {
        // fuzz test but check that caller is neither owner nor vault manager
        vm.assume(caller != alice && !IAccessControl(address(vault)).hasRole(ConcreteV2RolesLib.VAULT_MANAGER, caller));
        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(ITwoWayFeeSplitter.NeitherOwnerNorVaultManager.selector));
        feeSplitter.setMainRecipient(address(vault), bob);
        vm.stopPrank();
    }

    function test_setSecondaryRecipient() public {
        vm.startPrank(alice);
        feeSplitter.setFeeSplit(address(vault), 5000, alice, bob);
        vm.expectEmit(true, true, true, true);
        emit ITwoWayFeeSplitter.SecondaryRecipientSet(address(vault), charlie);
        feeSplitter.setSecondaryRecipient(address(vault), charlie);
        vm.stopPrank();
        // call getSecondaryRecipient
        address secondaryRecipient = feeSplitter.getSecondaryRecipient(address(vault));
        assertEq(secondaryRecipient, charlie, "secondary recipient should be charlie");
    }

    function test_fail_setSecondaryRecipient_WithoutPreviousFeeSplitBeingSet() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(ITwoWayFeeSplitter.InvalidFeeSplit.selector, 0, address(0), charlie));
        feeSplitter.setSecondaryRecipient(address(vault), charlie);
        vm.stopPrank();
    }

    function test_fail_setSecondaryRecipient_Unauthorized() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, bob));
        feeSplitter.setSecondaryRecipient(address(vault), charlie);
        vm.stopPrank();
    }

    function test_setFeeFraction(uint32 feeFraction) public {
        // fuzz test but check that fee fraction is less than BASIS_POINTS_DENOMINATOR
        vm.assume(feeFraction <= ConcreteV2ConstantsLib.BASIS_POINTS_DENOMINATOR);
        vm.startPrank(alice);
        feeSplitter.setFeeSplit(address(vault), 5000, alice, bob);
        vm.expectEmit(true, true, true, true);
        emit ITwoWayFeeSplitter.FeeFractionSet(address(vault), feeFraction);
        feeSplitter.setFeeFraction(address(vault), feeFraction);
        vm.stopPrank();
        // call getFeeFractionForSecondaryRecipient
        uint32 actualFeeFraction = feeSplitter.getFeeFractionForSecondaryRecipient(address(vault));
        assertEq(actualFeeFraction, feeFraction, "fee fraction should be the new fee fraction");
    }

    function test_fail_setFeeFraction_OutOfBounds(uint32 feeFraction) public {
        vm.assume(feeFraction > ConcreteV2ConstantsLib.BASIS_POINTS_DENOMINATOR);
        vm.startPrank(alice);
        vm.expectRevert(ITwoWayFeeSplitter.FeeFractionOutOfBounds.selector);
        feeSplitter.setFeeFraction(address(vault), feeFraction);
        vm.stopPrank();
    }

    function test_rescueFunds() public {
        // mint 1000000 tokens to vault
        vault.mint(address(feeSplitter), 1000000);
        // prank alice
        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit ITwoWayFeeSplitter.TokensRescued(address(vault), 1000000);
        feeSplitter.rescueTokens(address(vault));
        vm.stopPrank();
        // check that the balance of the vault is 0
        assertEq(vault.balanceOf(address(feeSplitter)), 0, "vault balance should be 0");
        // check that the balance of the alice is 1000000
        assertEq(vault.balanceOf(alice), 1000000, "alice balance should be 1000000");
    }

    function test_fail_rescueFunds_Unauthorized() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, bob));
        feeSplitter.rescueTokens(address(vault));
        vm.stopPrank();
    }

    function test_fail_rescueFunds_InvalidToken() public {
        vm.startPrank(alice);
        // set fee split
        feeSplitter.setFeeSplit(address(vault), 5000, alice, bob);
        vm.expectRevert(abi.encodeWithSelector(ITwoWayFeeSplitter.InvalidToken.selector, address(0)));
        feeSplitter.rescueTokens(address(0));
        vm.expectRevert(abi.encodeWithSelector(ITwoWayFeeSplitter.InvalidToken.selector, address(vault)));
        feeSplitter.rescueTokens(address(vault));
        vm.stopPrank();
    }

    function _initializeFeeSplitter(uint8 feeType, address owner) public returns (TwoWayFeeSplitter _feeSplitter) {
        _feeSplitter = TwoWayFeeSplitter(Clones.clone(feeSplitterImpl));
        _feeSplitter.initialize(owner, feeType);
    }
}
