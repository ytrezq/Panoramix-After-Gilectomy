// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Base } from "../Base.sol";
import { Errors } from "@merkl/utils/Errors.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import { ISwapper } from "src/interfaces/ISwapper.sol";
import { Swapper } from "src/Swapper.sol";
import { MockERC20 } from "@mocks/MockERC20.sol";
import { PayableReceiver } from "../mocks/PayableReceiver.sol";
import { NonPayableReceiver } from "../mocks/NonPayableReceiver.sol";

contract SwapperTest is Base {
    address[] internal tokens;
    uint256[] internal amounts;

    function setUp() public override {
        super.setUp();

        tokens.push(tokenA);
        tokens.push(tokenB);

        amounts.push(50e18);
        amounts.push(15e18);
    }

    function testRevert_IfAutoCompoundConfigInvalid() public {
        vm.expectRevert(ISwapper.PctTooBig.selector);
        swapper.claimAndSwap(
            ISwapper.Claim(new address[](0), new uint256[](0), new bytes32[][](0)), new Action[](0), BASIS_POINTS + 1
        );
    }

    function testRevert_IfInvalidProof() public {
        uint256[] memory newAmounts = amounts;
        newAmounts[1] = 17e18; // change amount.

        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(alice, tokens, newAmounts);

        vm.expectRevert(Errors.InvalidProof.selector);
        vm.prank(alice, alice);
        swapper.claimAndSwap(ISwapper.Claim(tokens, amounts, proofs), new Action[](0), 0);
    }

    function testRevert_IfAliceClaimsWithBobsProof() public {
        // Generate proof for bob
        (bytes32[][] memory bobProofs,) = merkleTreeHelper.buildMerkleTree(bob, tokens, amounts);

        // Alice tries to claim using Bob's proof
        vm.expectRevert(Errors.InvalidProof.selector);
        vm.prank(alice, alice);
        swapper.claimAndSwap(ISwapper.Claim(tokens, amounts, bobProofs), new Action[](0), 0);
    }

    function testRevert_IfAtLeastOneActionFails() public {
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(alice, tokens, amounts);

        Action[] memory actions = new Action[](1);
        actions[0].to = address(this);
        actions[0].data = "0x11111111";

        ISwapper.Claim memory claim = ISwapper.Claim(tokens, amounts, proofs);

        vm.expectRevert();
        vm.prank(alice, alice);
        swapper.claimAndSwap(claim, actions, 0);
    }

    // both tokens are swapped into kat but autocompound is false, hence all kat tokens go to the user.
    function test_MultipleTokensSwappedAndAutoCompoundIsFalse() public {
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(alice, tokens, amounts);
        Action[] memory actions = swapActionsBuilder.buildSwapActions(tokens, amounts, address(escrowToken), alice);

        assertEq(escrowToken.balanceOf(alice), 0);
        vm.prank(alice, alice);
        swapper.claimAndSwap(ISwapper.Claim(tokens, amounts, proofs), actions, 0);

        assertEq(escrowToken.balanceOf(alice), 130e18);
    }

    // both tokens are swapped into kat and autocompound is true, hence
    // creates lock with some portion to locked and rest goes to user.
    function test_MultipleTokensSwappedAndCompoundIsEnabled() public {
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(alice, tokens, amounts);
        Action[] memory actions =
            swapActionsBuilder.buildSwapActions(tokens, amounts, address(escrowToken), address(swapper));

        uint256 pct = 1000; // 10% in basis points
        uint256 lockAmount = (pct * 130e18) / BASIS_POINTS;

        assertEq(escrowToken.balanceOf(alice), 0);

        bytes[] memory execResults = swapActionsBuilder.mockSwapReturnData(amounts);
        vm.expectEmit();
        emit ISwapper.ClaimAndSwapped(alice, tokens, amounts, pct, ISwapper.Locked(2, lockAmount), actions, execResults);
        vm.prank(alice, alice);
        (uint256 diff, uint256 tokenId) = swapper.claimAndSwap(ISwapper.Claim(tokens, amounts, proofs), actions, pct);

        assertEq(diff, 130e18);
        assertEq(escrow.locked(tokenId).amount, lockAmount);
        assertEq(escrowToken.balanceOf(alice), 130e18 - lockAmount);
    }

    // Only single token is swapped into kat and compound is enabled,
    // hence some portion goes to newly created lock, rest goes to user.
    function test_SingleTokenSwappedAndCompoundIsEnabled() public {
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(alice, tokens, amounts);

        address[] memory outTokens = new address[](2);
        address[] memory recipients = new address[](2);
        outTokens[0] = address(escrowToken);
        outTokens[1] = address(tokenC);
        recipients[0] = address(swapper);
        recipients[1] = alice;

        Action[] memory actions = swapActionsBuilder.buildSwapActions(tokens, amounts, outTokens, recipients);

        assertEq(escrowToken.balanceOf(alice), 0);

        uint256 pct = 1000; // 10% in basis points
        uint256 lockAmount = (pct * 100e18) / BASIS_POINTS;

        bytes[] memory execResults = swapActionsBuilder.mockSwapReturnData(amounts);
        vm.expectEmit();
        emit ISwapper.ClaimAndSwapped(alice, tokens, amounts, pct, ISwapper.Locked(2, lockAmount), actions, execResults);
        vm.prank(alice, alice);
        (uint256 diff, uint256 tokenId) = swapper.claimAndSwap(ISwapper.Claim(tokens, amounts, proofs), actions, pct);

        assertEq(diff, 100e18);
        assertEq(escrow.locked(tokenId).amount, lockAmount);
        assertEq(escrowToken.balanceOf(alice), 100e18 - lockAmount);
    }

    // no tokens are swapped into kat, hence no kat increase on user.
    function test_NoTokenIsSwappedIntoKat() public {
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(alice, tokens, amounts);
        Action[] memory actions = swapActionsBuilder.buildSwapActions(tokens, amounts, tokenC, alice);

        uint256 aliceBalanceBeforeOnTokenC = MockERC20(tokenC).balanceOf(alice);

        assertEq(escrowToken.balanceOf(alice), 0);

        vm.expectEmit();
        bytes[] memory execResults = swapActionsBuilder.mockSwapReturnData(amounts);
        emit ISwapper.ClaimAndSwapped(alice, tokens, amounts, 1000, ISwapper.Locked(0, 0), actions, execResults);
        vm.prank(alice, alice);
        (uint256 diff,) = swapper.claimAndSwap(ISwapper.Claim(tokens, amounts, proofs), actions, 1000);

        assertEq(escrowToken.balanceOf(alice), 0);
        assertEq(diff, 0);
        assertGt(MockERC20(tokenC).balanceOf(alice), aliceBalanceBeforeOnTokenC);
    }

    function testRevert_DirectRewardDistributorCall() public {
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(alice, tokens, amounts);

        // Create action that tries to call reward distributor directly
        Action[] memory forbiddenActions = new Action[](1);
        forbiddenActions[0] =
            Action({ to: address(merklDistributor), value: 0, data: abi.encodeWithSignature("someFunction()") });

        vm.expectRevert(ISwapper.RewardDistributorCallForbidden.selector);
        vm.prank(alice, alice);
        swapper.claimAndSwap(ISwapper.Claim(tokens, amounts, proofs), forbiddenActions, 0);
    }

    function test_ClaimAndSwapWithEthValue() public {
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(alice, tokens, amounts);

        // Create a mock payable contract to receive ETH
        PayableReceiver receiver = new PayableReceiver();

        // Create action that sends ETH
        Action[] memory actionsWithValue = new Action[](1);
        actionsWithValue[0] =
            Action({ to: address(receiver), value: 1 ether, data: abi.encodeWithSignature("receiveEth()") });

        // Fund alice with ETH
        vm.deal(alice, 2 ether);

        uint256 receiverBalanceBefore = address(receiver).balance;

        vm.prank(alice, alice);
        swapper.claimAndSwap{ value: 1 ether }(ISwapper.Claim(tokens, amounts, proofs), actionsWithValue, 0);

        assertEq(address(receiver).balance, receiverBalanceBefore + 1 ether, "Receiver should have received 1 ETH");
    }

    function test_ClaimAndSwapReturnsUnusedEth() public {
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(alice, tokens, amounts);

        // Create a mock payable contract that will return some ETH
        PayableReceiver receiver = new PayableReceiver();

        // Create action that sends 1 ETH but receiver returns 0.4 ETH back
        Action[] memory actionsWithValue = new Action[](1);
        actionsWithValue[0] = Action({
            to: address(receiver),
            value: 1 ether,
            data: abi.encodeWithSignature("receiveEthAndReturnSome(uint256)", 0.4 ether)
        });

        // Fund alice with ETH
        vm.deal(alice, 2 ether);

        uint256 aliceBalanceBefore = alice.balance;
        uint256 receiverBalanceBefore = address(receiver).balance;

        vm.prank(alice, alice);
        swapper.claimAndSwap{ value: 1 ether }(ISwapper.Claim(tokens, amounts, proofs), actionsWithValue, 0);

        assertEq(address(receiver).balance, receiverBalanceBefore + 0.6 ether, "Receiver should have kept 0.6 ETH");
        assertEq(alice.balance, aliceBalanceBefore - 0.6 ether, "Alice should have received unused ETH back");
    }

    function test_WithdrawNativeDoesNotRevertWhenCallerCannotReceiveEth() public {
        // Create a non-payable contract that will call swapper
        NonPayableReceiver nonPayable = new NonPayableReceiver();
        vm.prank(address(nonPayable), address(nonPayable));

        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(address(nonPayable), tokens, amounts);
        Action[] memory actions =
            swapActionsBuilder.buildSwapActions(tokens, amounts, address(escrowToken), address(swapper));

        vm.startPrank(address(nonPayable), address(nonPayable));
        for (uint256 i = 0; i < tokens.length; i++) {
            merklDistributor.setClaimRecipient(address(swapper), tokens[i]);
        }
        vm.stopPrank();

        // Fund swapper with ETH
        vm.deal(address(swapper), 1 ether);

        uint256 swapperEthBefore = address(swapper).balance;

        // NonPayable contract calls claimAndSwap - should not revert even though it can't receive ETH
        vm.prank(address(nonPayable), address(nonPayable));
        swapper.claimAndSwap(ISwapper.Claim(tokens, amounts, proofs), actions, 0);

        // ETH should remain in swapper since nonPayable can't receive it
        assertEq(address(swapper).balance, swapperEthBefore, "ETH should remain in swapper");
        assertEq(address(nonPayable).balance, 0, "NonPayable should not have received ETH");
    }
}
