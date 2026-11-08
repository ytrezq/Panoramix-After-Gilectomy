// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { console2 as console, Test, Vm } from "../../modules/forge-std/src/Test.sol";

import { SyrupDrip } from "../../contracts/SyrupDrip.sol";

import { MerkleBase } from "../utils/MerkleBase.sol";

import { IRdtLike, TestBase } from "./TestBase.t.sol";

contract SyrupDripTestBase is TestBase {

    event Allocated(bytes32 indexed root, uint256 deadline, uint256 maxId);
    event Claimed(uint256 indexed id, address indexed account, uint256 amount);
    event Reclaimed(address indexed account, uint256 amount);
    event Staked(uint256 indexed id, address indexed account, uint256 assets, uint256 shares);

    SyrupDrip drip;

    function setUp() public virtual override {
        super.setUp();

        drip = new SyrupDrip(address(syrup), address(globals), address(stsyrup));
    }

}

contract AllocateIntegrationTests is SyrupDripTestBase {

    // Root of a Merkle tree generated from 4 token allocations.
    bytes32 root = 0x5a330af1653e87ea30d8bf559f0288a1268a5f87de5bb138c321b95c1fdf62b7;

    uint256 deadline = block.timestamp + 30 days;
    uint256 maxId    = 3;

    function test_allocate_notAuthorized() external {
        vm.expectRevert("SD:NOT_AUTHORIZED");
        drip.allocate(root, deadline, maxId);
    }

    function test_allocate_expiredDeadline_governor() external {
        vm.prank(governor.addr);
        vm.expectRevert("SD:A:INVALID_DEADLINE");
        drip.allocate(root, block.timestamp - 1 seconds, maxId);
    }

    function test_allocate_expiredDeadline_operationalAdmin() external {
        vm.prank(operationalAdmin.addr);
        vm.expectRevert("SD:A:INVALID_DEADLINE");
        drip.allocate(root, block.timestamp - 1 seconds, maxId);
    }

    function test_allocate_invalidMaxId() external {
        vm.prank(operationalAdmin.addr);
        drip.allocate(root, deadline, maxId);

        vm.prank(operationalAdmin.addr);
        vm.expectRevert("SD:A:INVALID_MAX_ID");
        drip.allocate(root, deadline, maxId - 1);
    }

    function test_allocate_success_governor() external {
        vm.expectEmit();
        emit Allocated(root, deadline, maxId);

        vm.prank(governor.addr);
        drip.allocate(root, deadline, maxId);

        assertEq(drip.root(),     root);
        assertEq(drip.deadline(), deadline);
        assertEq(drip.maxId(),    maxId);
    }

    function test_allocate_success_operationalAdmin() external {
        vm.expectEmit();
        emit Allocated(root, deadline, maxId);

        vm.prank(operationalAdmin.addr);
        drip.allocate(root, deadline, maxId);

        assertEq(drip.root(),     root);
        assertEq(drip.deadline(), deadline);
        assertEq(drip.maxId(),    maxId);
    }

}

contract ClaimIntegrationTests is SyrupDripTestBase, MerkleBase {

    uint256 funding = 30e18;

    function setUp() public override {
        super.setUp();

        setUpProofs();

        mintSyrup(address(drip), funding);

        vm.prank(operationalAdmin.addr);
        drip.allocate(root, deadline, maxId);
    }

    function test_claim_alreadyClaimed() external {
        drip.claim(id_habibi, address_habibi, amount_habibi, proof_habibi);

        vm.expectRevert("SD:C:ALREADY_CLAIMED");
        drip.claim(id_habibi, address_habibi, amount_habibi, proof_habibi);
    }

    function test_claim_expiredDeadline() external {
        vm.warp(deadline + 1 seconds);
        vm.expectRevert("SD:C:EXPIRED_DEADLINE");
        drip.claim(id_habibi, address_habibi, amount_habibi, proof_habibi);
    }

    function test_claim_invalidProof_id() external {
        vm.expectRevert("SD:C:INVALID_PROOF");
        drip.claim(id_habibi + 1, address_habibi, amount_habibi, proof_habibi);
    }

    function test_claim_invalidProof_account() external {
        vm.expectRevert("SD:C:INVALID_PROOF");
        drip.claim(id_habibi, address_chad, amount_habibi, proof_habibi);
    }

    function test_claim_invalidProof_amount() external {
        vm.expectRevert("SD:C:INVALID_PROOF");
        drip.claim(id_habibi, address_habibi, amount_habibi + 1, proof_habibi);
    }

    function test_claim_invalidProof_proof() external {
        proof_habibi[1] = bytes32(uint256(proof_habibi[1]) - 1);

        vm.expectRevert("SD:C:INVALID_PROOF");
        drip.claim(id_habibi, address_habibi, amount_habibi, proof_habibi);
    }

    function test_claim_transferFail() external {
        burnSyrup(address(drip), funding);

        vm.expectRevert("SD:C:TRANSFER_FAIL");
        drip.claim(id_habibi, address_habibi, amount_habibi, proof_habibi);
    }

    function test_claim_success_singleClaim() external {
        assertEq(syrup.balanceOf(address(drip)),           funding);
        assertEq(syrup.balanceOf(address(address_habibi)), 0);

        assertEq(drip.bitmaps(0), 0);
        assertEq(drip.bitmaps(1), 0);

        vm.expectEmit();
        emit Claimed(id_habibi, address_habibi, amount_habibi);

        drip.claim(id_habibi, address_habibi, amount_habibi, proof_habibi);

        assertEq(syrup.balanceOf(address(drip)),           funding - amount_habibi);
        assertEq(syrup.balanceOf(address(address_habibi)), amount_habibi);

        assertEq(drip.bitmaps(0), 2 ** id_habibi);
        assertEq(drip.bitmaps(1), 0);
    }

    function test_claim_success_multipleClaims() external {
        assertEq(syrup.balanceOf(address(drip)),           funding);
        assertEq(syrup.balanceOf(address(address_chad)),   0);
        assertEq(syrup.balanceOf(address(address_habibi)), 0);

        assertEq(drip.bitmaps(0), 0);
        assertEq(drip.bitmaps(1), 0);

        vm.expectEmit();
        emit Claimed(id_chad, address_chad, amount_chad);

        drip.claim(id_chad, address_chad, amount_chad, proof_chad);

        assertEq(syrup.balanceOf(address(drip)),           funding - amount_chad);
        assertEq(syrup.balanceOf(address(address_chad)),   amount_chad);
        assertEq(syrup.balanceOf(address(address_habibi)), 0);

        assertEq(drip.bitmaps(0), 2 ** id_chad);
        assertEq(drip.bitmaps(1), 0);

        vm.expectEmit();
        emit Claimed(id_habibi, address_habibi, amount_habibi);

        drip.claim(id_habibi, address_habibi, amount_habibi, proof_habibi);

        assertEq(syrup.balanceOf(address(drip)),           funding - amount_chad - amount_habibi);
        assertEq(syrup.balanceOf(address(address_chad)),   amount_chad);
        assertEq(syrup.balanceOf(address(address_habibi)), amount_habibi);

        assertEq(drip.bitmaps(0), 2 ** id_chad + 2 ** id_habibi);
        assertEq(drip.bitmaps(1), 0);
    }

    function test_claim_success_multipleSlots() external {
        assertEq(syrup.balanceOf(address(drip)),          funding);
        assertEq(syrup.balanceOf(address(address_chad)),  0);
        assertEq(syrup.balanceOf(address(address_degen)), 0);

        assertEq(drip.bitmaps(0), 0);
        assertEq(drip.bitmaps(1), 0);

        vm.expectEmit();
        emit Claimed(id_chad, address_chad, amount_chad);

        drip.claim(id_chad, address_chad, amount_chad, proof_chad);

        assertEq(syrup.balanceOf(address(drip)),          funding - amount_chad);
        assertEq(syrup.balanceOf(address(address_chad)),  amount_chad);
        assertEq(syrup.balanceOf(address(address_degen)), 0);

        assertEq(drip.bitmaps(0), 2 ** id_chad);
        assertEq(drip.bitmaps(1), 0);

        vm.expectEmit();
        emit Claimed(id_degen, address_degen, amount_degen);

        drip.claim(id_degen, address_degen, amount_degen, proof_degen);

        assertEq(syrup.balanceOf(address(drip)),          funding - amount_chad - amount_degen);
        assertEq(syrup.balanceOf(address(address_chad)),  amount_chad);
        assertEq(syrup.balanceOf(address(address_degen)), amount_degen);

        assertEq(drip.bitmaps(0), 2 ** id_chad);
        assertEq(drip.bitmaps(1), 0);
        assertEq(drip.bitmaps(2), 0);
        assertEq(drip.bitmaps(3), 0);
        assertEq(drip.bitmaps(4), 0);
        assertEq(drip.bitmaps(5), 2 ** (id_degen % 256));
    }

    function test_claim_success_multipleInstances() external {
        assertEq(syrup.balanceOf(address(drip)),         funding);
        assertEq(syrup.balanceOf(address(address_chad)), 0);

        assertEq(drip.bitmaps(0), 0);
        assertEq(drip.bitmaps(1), 0);

        vm.expectEmit();
        emit Claimed(id_chad, address_chad, amount_chad);

        drip.claim(id_chad, address_chad, amount_chad, proof_chad);

        assertEq(syrup.balanceOf(address(drip)),         funding - amount_chad);
        assertEq(syrup.balanceOf(address(address_chad)), amount_chad);

        assertEq(drip.bitmaps(0), 2 ** id_chad);
        assertEq(drip.bitmaps(1), 0);

        vm.expectEmit();
        emit Claimed(id_chad2, address_chad2, amount_chad2);

        drip.claim(id_chad2, address_chad2, amount_chad2, proof_chad2);

        assertEq(syrup.balanceOf(address(drip)),         funding - amount_chad - amount_chad2);
        assertEq(syrup.balanceOf(address(address_chad)), amount_chad + amount_chad2);

        assertEq(drip.bitmaps(0), 2 ** id_chad + 2 ** id_chad2);
        assertEq(drip.bitmaps(1), 0);
    }

    function test_claim_success_zeroAmount() external {
        assertEq(syrup.balanceOf(address(drip)),         funding);
        assertEq(syrup.balanceOf(address(address_zero)), 0);

        assertEq(drip.bitmaps(0), 0);
        assertEq(drip.bitmaps(1), 0);

        vm.expectEmit();
        emit Claimed(id_zero, address_zero, amount_zero);

        drip.claim(id_zero, address_zero, amount_zero, proof_zero);

        assertEq(syrup.balanceOf(address(drip)),         funding);
        assertEq(syrup.balanceOf(address(address_zero)), 0);

        assertEq(drip.bitmaps(0), 2 ** id_zero);
        assertEq(drip.bitmaps(1), 0);
    }

    function test_claim_success_duplicateId() external {
        assertEq(syrup.balanceOf(address(drip)),           funding);
        assertEq(syrup.balanceOf(address(address_habibi)), 0);

        assertEq(drip.bitmaps(0), 0);
        assertEq(drip.bitmaps(1), 0);

        vm.expectEmit();
        emit Claimed(id_habibi, address_habibi, amount_habibi);

        drip.claim(id_habibi, address_habibi, amount_habibi, proof_habibi);

        assertEq(syrup.balanceOf(address(drip)),           funding - amount_habibi);
        assertEq(syrup.balanceOf(address(address_habibi)), amount_habibi);

        assertEq(drip.bitmaps(0), 2 ** id_habibi);
        assertEq(drip.bitmaps(1), 0);

        vm.expectRevert("SD:C:ALREADY_CLAIMED");
        drip.claim(id_duplicate, address_duplicate, amount_duplicate, proof_duplicate);

        assertEq(id_habibi, id_duplicate);
    }

    function test_claim_success_updatedAllocation() external {
        assertEq(syrup.balanceOf(address(drip)),           funding);
        assertEq(syrup.balanceOf(address(address_habibi)), 0);
        assertEq(syrup.balanceOf(address(address_next)),   0);

        assertEq(drip.bitmaps(0), 0);
        assertEq(drip.bitmaps(1), 0);

        vm.expectEmit();
        emit Claimed(id_habibi, address_habibi, amount_habibi);

        drip.claim(id_habibi, address_habibi, amount_habibi, proof_habibi);

        assertEq(syrup.balanceOf(address(drip)),           funding - amount_habibi);
        assertEq(syrup.balanceOf(address(address_habibi)), amount_habibi);
        assertEq(syrup.balanceOf(address(address_next)),   0);

        assertEq(drip.bitmaps(0), 2 ** id_habibi);
        assertEq(drip.bitmaps(1), 0);

        // Update token allocations.
        vm.prank(operationalAdmin.addr);
        drip.allocate(root2, deadline, maxId);

        // Fail to claim from the old allocations.
        vm.expectRevert("SD:C:INVALID_PROOF");
        drip.claim(id_degen, address_degen, amount_degen, proof_degen);

        // Succeed claiming from the new allocations.
        vm.expectEmit();
        emit Claimed(id_next, address_next, amount_next);

        drip.claim(id_next, address_next, amount_next, proof_next);

        assertEq(syrup.balanceOf(address(drip)),           funding - amount_habibi - amount_next);
        assertEq(syrup.balanceOf(address(address_habibi)), amount_habibi);
        assertEq(syrup.balanceOf(address(address_next)),   amount_next);

        assertEq(drip.bitmaps(0), 2 ** id_habibi + 2 ** id_next);
        assertEq(drip.bitmaps(1), 0);
    }

}

contract ClaimAndStakeIntegrationTest is SyrupDripTestBase, MerkleBase {

    uint256 funding = 30e18;

    function setUp() public override {
        super.setUp();

        setUpProofs();

        mintSyrup(address(drip), funding);

        vm.prank(operationalAdmin.addr);
        drip.allocate(root, deadline, maxId);
    }

    function test_claimAndStake_zeroStakeAmount() external {
        vm.expectRevert("SD:CAS:ZERO_STAKE_AMOUNT");
        drip.claimAndStake(id_habibi, address_habibi, amount_habibi, 0, proof_habibi);
    }

    function test_claimAndStake_invalidStakeAmount() external {
        vm.expectRevert("SD:CAS:INVALID_STAKE_AMOUNT");
        drip.claimAndStake(id_habibi, address_habibi, amount_habibi, amount_habibi + 1, proof_habibi);
    }

    // Repeating the tests from Claim. Redundant but necessary for the sake of completeness.
    function test_claimAndStake_alreadyClaimed() external {
        drip.claimAndStake(id_habibi, address_habibi, amount_habibi, amount_habibi, proof_habibi);

        vm.expectRevert("SD:C:ALREADY_CLAIMED");
        drip.claimAndStake(id_habibi, address_habibi, amount_habibi, amount_habibi, proof_habibi);
    }

    function test_claimAndStake_expiredDeadline() external {
        vm.warp(deadline + 1 seconds);
        vm.expectRevert("SD:C:EXPIRED_DEADLINE");
        drip.claimAndStake(id_habibi, address_habibi, amount_habibi, amount_habibi, proof_habibi);
    }

    function test_claimAndStake_invalidProof_id() external {
        vm.expectRevert("SD:C:INVALID_PROOF");
        drip.claimAndStake(id_habibi + 1, address_habibi, amount_habibi, amount_habibi, proof_habibi);
    }

    function test_claimAndStake_invalidProof_account() external {
        vm.expectRevert("SD:C:INVALID_PROOF");
        drip.claimAndStake(id_habibi, address_chad, amount_habibi, amount_habibi, proof_habibi);
    }

    function test_claimAndStake_invalidProof_amount() external {
        vm.expectRevert("SD:C:INVALID_PROOF");
        drip.claimAndStake(id_habibi, address_habibi, amount_habibi + 1, amount_habibi, proof_habibi);
    }

    function test_claimAndStake_invalidProof_proof() external {
        proof_habibi[1] = bytes32(uint256(proof_habibi[1]) - 1);

        vm.expectRevert("SD:C:INVALID_PROOF");
        drip.claimAndStake(id_habibi, address_habibi, amount_habibi, amount_habibi, proof_habibi);
    }

    function test_claimAndStake_transferFail() external {
        burnSyrup(address(drip), funding);

        vm.expectRevert("SD:C:TRANSFER_FAIL");
        drip.claimAndStake(id_habibi, address_habibi, amount_habibi, 1, proof_habibi);
    }

    function test_claimAndStake_transferToStakeFail() external {
        burnSyrup(address(drip), funding);

        vm.expectRevert("RDT:M:TRANSFER_FROM");
        drip.claimAndStake(id_habibi, address_habibi, amount_habibi, amount_habibi, proof_habibi);
    }

    function test_claimAndStake_fullStake() external {
        assertEq(syrup.balanceOf(address(drip)),           funding);
        assertEq(syrup.balanceOf(address(address_chad)),   0);
        assertEq(syrup.balanceOf(address(address_habibi)), 0);

        assertEq(stsyrup.balanceOf(address_chad),   0);
        assertEq(stsyrup.balanceOf(address_habibi), 0);
        assertEq(stsyrup.balanceOf(address(drip)),  0);

        assertEq(drip.bitmaps(0), 0);
        assertEq(drip.bitmaps(1), 0);

        vm.expectEmit();
        emit Claimed(id_chad, address_chad, amount_chad);

        vm.expectEmit();
        emit Staked(id_chad, address_chad, amount_chad, amount_chad);

        vm.expectCall(address(stsyrup), abi.encodeWithSelector(IRdtLike.deposit.selector, amount_chad, address_chad));

        drip.claimAndStake(id_chad, address_chad, amount_chad, amount_chad, proof_chad);

        assertEq(syrup.balanceOf(address(drip)),           funding - amount_chad);
        assertEq(syrup.balanceOf(address(address_chad)),   0);
        assertEq(syrup.balanceOf(address(address_habibi)), 0);
        assertEq(syrup.balanceOf(address(stsyrup)),        amount_chad);

        assertEq(stsyrup.balanceOf(address_chad),   amount_chad);
        assertEq(stsyrup.balanceOf(address_habibi), 0);
        assertEq(stsyrup.balanceOf(address(drip)),  0);

        assertEq(drip.bitmaps(0), 2 ** id_chad);
        assertEq(drip.bitmaps(1), 0);
    }

    function test_claimAndStake_partialStake() external {
        assertEq(syrup.balanceOf(address(drip)),           funding);
        assertEq(syrup.balanceOf(address(address_chad)),   0);
        assertEq(syrup.balanceOf(address(address_habibi)), 0);

        assertEq(stsyrup.balanceOf(address_chad),   0);
        assertEq(stsyrup.balanceOf(address_habibi), 0);
        assertEq(stsyrup.balanceOf(address(drip)),  0);

        assertEq(drip.bitmaps(0), 0);
        assertEq(drip.bitmaps(1), 0);

        uint256 stakeAmount_chad = amount_chad / 10;

        vm.expectEmit();
        emit Claimed(id_chad, address_chad, amount_chad);

        vm.expectEmit();
        emit Staked(id_chad, address_chad, stakeAmount_chad, stakeAmount_chad);

        vm.expectCall(address(stsyrup), abi.encodeWithSelector(IRdtLike.deposit.selector, stakeAmount_chad, address_chad));

        drip.claimAndStake(id_chad, address_chad, amount_chad, stakeAmount_chad, proof_chad);

        assertEq(syrup.balanceOf(address(drip)),           funding - amount_chad);
        assertEq(syrup.balanceOf(address(address_chad)),   amount_chad - stakeAmount_chad);
        assertEq(syrup.balanceOf(address(address_habibi)), 0);
        assertEq(syrup.balanceOf(address(stsyrup)),        stakeAmount_chad);

        assertEq(stsyrup.balanceOf(address_chad),   stakeAmount_chad);
        assertEq(stsyrup.balanceOf(address_habibi), 0);
        assertEq(stsyrup.balanceOf(address(drip)),  0);

        assertEq(drip.bitmaps(0), 2 ** id_chad);
        assertEq(drip.bitmaps(1), 0);
    }

    function test_claimAndStake_success_multipleClaims() external {
        assertEq(syrup.balanceOf(address(drip)),           funding);
        assertEq(syrup.balanceOf(address(address_chad)),   0);
        assertEq(syrup.balanceOf(address(address_habibi)), 0);

        assertEq(stsyrup.balanceOf(address_chad),   0);
        assertEq(stsyrup.balanceOf(address_habibi), 0);
        assertEq(stsyrup.balanceOf(address(drip)),  0);

        assertEq(drip.bitmaps(0), 0);
        assertEq(drip.bitmaps(1), 0);

        uint256 stakeAmount_chad = amount_chad / 4;

        vm.expectEmit();
        emit Claimed(id_chad, address_chad, amount_chad);

        vm.expectEmit();
        emit Staked(id_chad, address_chad, stakeAmount_chad, stakeAmount_chad);

        vm.expectCall(address(stsyrup), abi.encodeWithSelector(IRdtLike.deposit.selector, stakeAmount_chad, address_chad));

        drip.claimAndStake(id_chad, address_chad, amount_chad, stakeAmount_chad, proof_chad);

        assertEq(syrup.balanceOf(address(drip)),           funding - amount_chad);
        assertEq(syrup.balanceOf(address(address_chad)),   amount_chad - stakeAmount_chad);
        assertEq(syrup.balanceOf(address(address_habibi)), 0);
        assertEq(syrup.balanceOf(address(stsyrup)),        stakeAmount_chad);

        assertEq(stsyrup.balanceOf(address_chad),   stakeAmount_chad);
        assertEq(stsyrup.balanceOf(address_habibi), 0);
        assertEq(stsyrup.balanceOf(address(drip)),  0);

        assertEq(drip.bitmaps(0), 2 ** id_chad);
        assertEq(drip.bitmaps(1), 0);

        uint256 stakeAmount_habibi = amount_habibi / 5;

        vm.expectCall(address(stsyrup), abi.encodeWithSelector(IRdtLike.deposit.selector, stakeAmount_habibi, address_habibi));

        vm.expectEmit();
        emit Claimed(id_habibi, address_habibi, amount_habibi);

        vm.expectEmit();
        emit Staked(id_habibi, address_habibi, stakeAmount_habibi, stakeAmount_habibi);

        drip.claimAndStake(id_habibi, address_habibi, amount_habibi, stakeAmount_habibi, proof_habibi);

        assertEq(syrup.balanceOf(address(drip)),           funding - amount_chad - amount_habibi);
        assertEq(syrup.balanceOf(address(address_chad)),   amount_chad - stakeAmount_chad);
        assertEq(syrup.balanceOf(address(address_habibi)), amount_habibi - stakeAmount_habibi);
        assertEq(syrup.balanceOf(address(stsyrup)),        stakeAmount_chad + stakeAmount_habibi);

        assertEq(stsyrup.balanceOf(address_chad),   stakeAmount_chad);
        assertEq(stsyrup.balanceOf(address_habibi), stakeAmount_habibi);
        assertEq(stsyrup.balanceOf(address(drip)),  0);

        assertEq(drip.bitmaps(0), 2 ** id_chad + 2 ** id_habibi);
        assertEq(drip.bitmaps(1), 0);
    }

    function test_claimAndStake_success_multipleInstances() external {
        assertEq(syrup.balanceOf(address(drip)),         funding);
        assertEq(syrup.balanceOf(address(address_chad)), 0);

        assertEq(drip.bitmaps(0), 0);
        assertEq(drip.bitmaps(1), 0);

        assertEq(stsyrup.balanceOf(address_chad),   0);
        assertEq(stsyrup.balanceOf(address(drip)),  0);

        vm.expectEmit();
        emit Claimed(id_chad, address_chad, amount_chad);

        vm.expectEmit();
        emit Staked(id_chad, address_chad, amount_chad, amount_chad);

        vm.expectCall(address(stsyrup), abi.encodeWithSelector(IRdtLike.deposit.selector, amount_chad, address_chad));

        drip.claimAndStake(id_chad, address_chad, amount_chad, amount_chad, proof_chad);

        assertEq(syrup.balanceOf(address(drip)),         funding - amount_chad);
        assertEq(syrup.balanceOf(address(address_chad)), 0);
        assertEq(syrup.balanceOf(address(stsyrup)),      amount_chad);

        assertEq(stsyrup.balanceOf(address_chad),   amount_chad);
        assertEq(stsyrup.balanceOf(address(drip)),  0);

        assertEq(drip.bitmaps(0), 2 ** id_chad);
        assertEq(drip.bitmaps(1), 0);

        uint256 stakeAmount_chad2 = amount_chad2 / 2;

        vm.expectEmit();
        emit Claimed(id_chad2, address_chad2, amount_chad2);

        vm.expectEmit();
        emit Staked(id_chad2, address_chad2, stakeAmount_chad2, stakeAmount_chad2);

        vm.expectCall(address(stsyrup), abi.encodeWithSelector(IRdtLike.deposit.selector, stakeAmount_chad2, address_chad2));

        drip.claimAndStake(id_chad2, address_chad2, amount_chad2, stakeAmount_chad2, proof_chad2);

        assertEq(syrup.balanceOf(address(drip)),         funding - amount_chad - amount_chad2);
        assertEq(syrup.balanceOf(address(address_chad)), amount_chad2 - stakeAmount_chad2);
        assertEq(syrup.balanceOf(address(stsyrup)),      amount_chad + stakeAmount_chad2);

        assertEq(stsyrup.balanceOf(address_chad),   amount_chad + stakeAmount_chad2);
        assertEq(stsyrup.balanceOf(address(drip)),  0);

        assertEq(drip.bitmaps(0), 2 ** id_chad + 2 ** id_chad2);
        assertEq(drip.bitmaps(1), 0);
    }

    function testFuzz_claimAndStake(uint256 stakeAmount) external {
        stakeAmount = bound(stakeAmount, 1, amount_degen);

        assertEq(syrup.balanceOf(address(drip)),          funding);
        assertEq(syrup.balanceOf(address(address_degen)), 0);

        assertEq(drip.bitmaps(0), 0);
        assertEq(drip.bitmaps(1), 0);

        assertEq(stsyrup.balanceOf(address_degen), 0);
        assertEq(stsyrup.balanceOf(address(drip)), 0);

        vm.expectEmit();
        emit Claimed(id_degen, address_degen, amount_degen);

        vm.expectEmit();
        emit Staked(id_degen, address_degen, stakeAmount, stakeAmount);

        vm.expectCall(address(stsyrup), abi.encodeWithSelector(IRdtLike.deposit.selector, stakeAmount, address_degen));

        drip.claimAndStake(id_degen, address_degen, amount_degen, stakeAmount, proof_degen);

        assertEq(syrup.balanceOf(address(drip)),          funding - amount_degen);
        assertEq(syrup.balanceOf(address(address_degen)), amount_degen - stakeAmount);
        assertEq(syrup.balanceOf(address(stsyrup)),       stakeAmount);

        assertEq(stsyrup.balanceOf(address_degen), stakeAmount);
        assertEq(stsyrup.balanceOf(address(drip)), 0);

        assertEq(drip.bitmaps(0), 0);
        assertEq(drip.bitmaps(1), 0);
        assertEq(drip.bitmaps(2), 0);
        assertEq(drip.bitmaps(3), 0);
        assertEq(drip.bitmaps(4), 0);
        assertEq(drip.bitmaps(5), 2 ** (id_degen % 256));
    }

}

contract ReclaimIntegrationTest is SyrupDripTestBase {

    address treasury = makeAddr("treasury");

    uint256 balance = 5e18;

    function setUp() public override {
        super.setUp();

        mintSyrup(address(drip), balance);
    }

    function test_reclaim_notAuthorized() external {
        vm.expectRevert("SD:NOT_AUTHORIZED");
        drip.reclaim(treasury, balance);
    }

    function test_reclaim_zeroAmount() external {
        vm.prank(governor.addr);
        vm.expectRevert("SD:R:ZERO_AMOUNT");
        drip.reclaim(treasury, 0);
    }

    function test_reclaim_transferFail() external {
        vm.prank(governor.addr);
        vm.expectRevert("SD:R:TRANSFER_FAIL");
        drip.reclaim(treasury, balance + 1);
    }

    function test_reclaim_success_governor() external {
        vm.expectEmit();
        emit Reclaimed(treasury, balance);

        assertEq(syrup.balanceOf(address(drip)),     balance);
        assertEq(syrup.balanceOf(address(treasury)), 0);

        vm.prank(governor.addr);
        drip.reclaim(treasury, balance);

        assertEq(syrup.balanceOf(address(drip)),     0);
        assertEq(syrup.balanceOf(address(treasury)), balance);
    }

    function test_reclaim_success_operationalAdmin() external {
        vm.expectEmit();
        emit Reclaimed(treasury, balance);

        assertEq(syrup.balanceOf(address(drip)),     balance);
        assertEq(syrup.balanceOf(address(treasury)), 0);

        vm.prank(operationalAdmin.addr);
        drip.reclaim(treasury, balance);

        assertEq(syrup.balanceOf(address(drip)),     0);
        assertEq(syrup.balanceOf(address(treasury)), balance);
    }

}
