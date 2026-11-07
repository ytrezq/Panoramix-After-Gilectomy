// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Setup } from "test/utils/Setup.sol";
import { YToken } from "src/YToken.sol";
import { Locker } from "src/Locker.sol";
import { Operator } from "src/Operator.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

contract YTokenTest is Setup {
    address public user = address(0x123);
    address public recipient = address(0x456);

    function setUp() public override {
        super.setUp();
        toggleInfiniteLock(address(locker), true);
    }

    // ============================================
    // Constructor Tests
    // ============================================

    function test_ConstructorSetsImmutables() public {
        YToken newToken = new YToken(
            address(locker),
            address(token),
            "Test Token",
            "TEST"
        );

        assertEq(address(newToken.locker()), address(locker));
        assertEq(address(newToken.token()), address(token));
        assertEq(newToken.name(), "Test Token");
        assertEq(newToken.symbol(), "TEST");
    }

    // ============================================
    // Lock Function Tests
    // ============================================

    function test_LockTransfersTokensAndMintsYTokens() public {
        uint256 lockAmount = 10_000e18;
        deal(address(token), user, lockAmount);

        vm.startPrank(user);
        token.approve(address(yToken), lockAmount);

        uint256 recipientYTokenBefore = yToken.balanceOf(recipient);
        uint256 operatorLockedBefore = operator.getLockedAmount();

        // capture current ve supply before lock (the ve contract exposes it as `supply()` or equivalent)
        uint256 supplyBefore = escrow.supply();

        YToken(address(yToken)).mint(lockAmount, recipient);
        vm.stopPrank();

        // compute the effective rounded value used by the ve contract
        uint256 UMAXTIME = 4 * 365 days; // or import from the ve interface if exposed
        uint256 newSupply = (supplyBefore + lockAmount) / UMAXTIME * UMAXTIME;
        uint256 roundedValue = newSupply - supplyBefore;

        assertEq(token.balanceOf(user), 0);
        assertEq(yToken.balanceOf(recipient), recipientYTokenBefore + lockAmount);
        assertEq(operator.getLockedAmount(), operatorLockedBefore + roundedValue);
    }

    function test_LockRevertsWithZeroAmount() public {
        // given: User tries to lock zero tokens
        vm.startPrank(user);

        // when/then: Lock reverts with zero amount
        vm.expectRevert("Amount must be > 0");
        YToken(address(yToken)).mint(0, recipient);
        vm.stopPrank();
    }

    function test_LockMintsToSpecifiedRecipient() public {
        // given: User locks but specifies different recipient
        uint256 lockAmount = 5_000e18;
        deal(address(token), user, lockAmount);

        vm.startPrank(user);
        token.approve(address(yToken), lockAmount);

        // when: User locks to a different address
        YToken(address(yToken)).mint(lockAmount, recipient);
        vm.stopPrank();

        // then: Recipient receives yTokens, not the user
        assertEq(yToken.balanceOf(recipient), lockAmount);
        assertEq(yToken.balanceOf(user), 0);
    }

    // ============================================
    // Mint Function Tests
    // ============================================

    function test_MintCreatesTokens() public {
        // given: Operator wants to mint tokens
        uint256 mintAmount = 100_000e18;
        uint256 recipientBalanceBefore = yToken.balanceOf(recipient);

        // when: Operator calls mint
        vm.prank(address(operator));
        YToken(address(yToken)).mint(mintAmount, recipient);

        // then: Tokens are minted to recipient
        assertEq(yToken.balanceOf(recipient), recipientBalanceBefore + mintAmount);
    }

    // ============================================
    // Sweep Function Tests
    // ============================================

    function test_SweepTransfersTokens() public {
        // given: Some ERC20 tokens are in the yToken contract
        MockERC20 someToken = new MockERC20("Some", "SOME");
        someToken.mint(address(yToken), 1000e18);

        uint256 sweepAmount = 500e18;
        uint256 recipientBalanceBefore = someToken.balanceOf(recipient);

        // when: Operator sweeps tokens
        vm.prank(address(operator));
        YToken(address(yToken)).sweep(address(someToken), recipient, sweepAmount);

        // then: Tokens transferred to recipient
        assertEq(someToken.balanceOf(recipient), recipientBalanceBefore + sweepAmount);
        assertEq(someToken.balanceOf(address(yToken)), 500e18);
    }

    function test_SweepRevertsWhenUnauthorized() public {
        MockERC20 someToken = new MockERC20("Some", "SOME");
        someToken.mint(address(yToken), 1000e18);

        vm.expectRevert("!authorized");
        vm.prank(user);
        YToken(address(yToken)).sweep(address(someToken), recipient, 500e18);
    }

    function test_SweepSucceedsWhenCalledByOwner() public {
        MockERC20 someToken = new MockERC20("Some", "SOME");
        someToken.mint(address(yToken), 1000e18);

        uint256 sweepAmount = 500e18;
        uint256 recipientBalanceBefore = someToken.balanceOf(recipient);

        vm.prank(YToken(address(yToken)).owner());
        YToken(address(yToken)).sweep(address(someToken), recipient, sweepAmount);

        assertEq(someToken.balanceOf(recipient), recipientBalanceBefore + sweepAmount);
        assertEq(someToken.balanceOf(address(yToken)), 500e18);
    }

    // ============================================
    // setLocker Function Tests
    // ============================================

    function test_SetLockerUpdatesOperatorAndOwnerReferences() public {
        address newOwner = address(0x999);
        YToken yt = YToken(address(yToken));

        address predictedLockerAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        deal(address(token), predictedLockerAddress, 1e18);

        Locker newLocker = new Locker(newOwner, address(token), address(escrow));
        Operator newOperator = new Operator(payable(address(newLocker)), address(gaugeController), address(daoVoting), address(yToken));

        vm.prank(newOwner);
        newLocker.setOperator(address(newOperator));

        toggleInfiniteLock(address(newLocker), true);

        address oldOperator = yt.operator();
        address oldOwner = yt.owner();

        vm.prank(yt.owner());
        yt.setLocker(address(newLocker));

        assertEq(address(yt.locker()), address(newLocker));
        assertEq(yt.operator(), address(newOperator));
        assertEq(yt.owner(), newOwner);
        assertTrue(yt.operator() != oldOperator);
        assertTrue(yt.owner() != oldOwner);
    }

    function test_SetLockerSucceedsWhenCalledByOwner() public {
        address newOwner = address(0x888);
        YToken yt = YToken(address(yToken));

        address predictedLockerAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        deal(address(token), predictedLockerAddress, 1e18);

        Locker newLocker = new Locker(newOwner, address(token), address(escrow));
        toggleInfiniteLock(address(newLocker), true);

        vm.prank(yt.owner());
        yt.setLocker(address(newLocker));

        assertEq(address(yt.locker()), address(newLocker));
    }

    function test_SetLockerRevertsWithZeroAddress() public {
        YToken yt = YToken(address(yToken));
        address owner = yt.owner();

        vm.expectRevert("!valid");
        vm.prank(owner);
        yt.setLocker(address(0));
    }

    function test_SetLockerRevertsWhenUnauthorized() public {
        address predictedLockerAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        deal(address(token), predictedLockerAddress, 1e18);

        Locker newLocker = new Locker(address(0x777), address(token), address(escrow));
        toggleInfiniteLock(address(newLocker), true);

        vm.expectRevert("!authorized");
        vm.prank(user);
        YToken(address(yToken)).setLocker(address(newLocker));
    }
}
