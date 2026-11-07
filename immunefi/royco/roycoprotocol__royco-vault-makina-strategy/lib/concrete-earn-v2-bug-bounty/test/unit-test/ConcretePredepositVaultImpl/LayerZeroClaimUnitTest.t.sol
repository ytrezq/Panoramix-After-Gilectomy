// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ConcretePredepositVaultImplBaseSetup} from "../../common/ConcretePredepositVaultImplBaseSetup.t.sol";
import {IConcretePredepositVaultImpl} from "../../../src/interface/IConcretePredepositVaultImpl.sol";
import {IPredepostVaultOApp} from "../../../src/periphery/interface/IPredepostVaultOApp.sol";
import {PredepostVaultOApp} from "../../../src/periphery/predeposit/PredepostVaultOApp.sol";
import {MessagingFee} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {ERC4626StrategyMock} from "../../mock/ERC4626StrategyMock.sol";
import {IAllocateModule} from "../../../src/interface/IAllocateModule.sol";
import {IAccessControl} from "@openzeppelin-contracts/access/IAccessControl.sol";
import {ConcreteV2RolesLib as RolesLib} from "../../../src/lib/Roles.sol";
import {IConcreteStandardVaultImpl} from "../../../src/interface/IConcreteStandardVaultImpl.sol";

contract LayerZeroClaimUnitTest is ConcretePredepositVaultImplBaseSetup {
    using OptionsBuilder for bytes;

    address public user1;
    address public user2;

    ERC4626StrategyMock public strategy;

    event SharesClaimedOnTargetChain(address indexed user, uint256 shares);

    function setUp() public override {
        super.setUp();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Fund user accounts with assets
        asset.mint(user1, 10000e18);
        asset.mint(user2, 10000e18);

        // Fund users with ETH for LayerZero fees
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(vaultManager, 10 ether); // Fund manager for batch claims

        // Approve vault A
        vm.prank(user1);
        asset.approve(address(predepositVault), 10000e18);

        vm.prank(user2);
        asset.approve(address(predepositVault), 10000e18);

        // Deploy and setup strategy
        strategy = new ERC4626StrategyMock(address(asset));
        vm.prank(strategyOperator);
        predepositVault.addStrategy(address(strategy));

        // Add strategy to deallocation order
        address[] memory order = new address[](1);
        order[0] = address(strategy);
        vm.prank(allocator);
        predepositVault.setDeallocationOrder(order);

        // Users deposit into vault A
        vm.prank(user1);
        predepositVault.deposit(5000e18, user1);

        vm.prank(user2);
        predepositVault.deposit(3000e18, user2);

        // Allocate all assets to strategy (simulating assets being bridged away)
        _allocateAllToStrategy();

        // Lock deposits and withdrawals before allowing claims
        vm.startPrank(vaultManager);
        predepositVault.setDepositLimits(0, 0);
        predepositVault.setWithdrawLimits(0, 0);
        vm.stopPrank();
    }

    /// @dev Helper function to allocate all vault assets to the strategy
    function _allocateAllToStrategy() internal {
        uint256 amount = predepositVault.cachedTotalAssets();
        if (amount > 0) {
            IAllocateModule.AllocateParams[] memory params = new IAllocateModule.AllocateParams[](1);
            params[0] = IAllocateModule.AllocateParams({
                isDeposit: true, strategy: address(strategy), extraData: abi.encode(amount)
            });
            vm.prank(allocator);
            predepositVault.allocate(abi.encode(params));
        }
    }

    function test_claimOnTargetChain_locksShares() public {
        uint256 user1SharesBefore = predepositVault.balanceOf(user1);
        assertGt(user1SharesBefore, 0, "User should have shares");

        // Check initial state on destination chain
        uint256 user1BVaultSharesBefore = destinationVault.balanceOf(user1);
        uint256 distributorSharesBefore = distributor.getAvailableShares();
        assertEq(user1BVaultSharesBefore, 0, "User should have no destinationVault shares initially");
        assertGt(distributorSharesBefore, 0, "Distributor should have shares");

        // Build options for the send operation
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        // Quote the fee via OApp
        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteClaimOnTargetChain(user1, options, false);

        vm.expectEmit(true, true, true, true);
        emit SharesClaimedOnTargetChain(user1, user1SharesBefore);

        // Perform the claim operation
        vm.prank(user1);
        predepositVault.claimOnTargetChain{value: fee.nativeFee}(options);

        // Verify that packets were sent correctly and delivered to distributor
        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // Check shares are burned on chain A
        uint256 user1SharesAfter = predepositVault.balanceOf(user1);

        assertEq(user1SharesAfter, 0, "User shares should be burned on chain A");

        // Check locked shares tracking
        uint256 lockedShares = predepositVault.getLockedShares(user1);
        assertEq(lockedShares, user1SharesBefore, "Locked shares should be tracked");

        // Check shares distributed on chain B
        uint256 user1BVaultSharesAfter = destinationVault.balanceOf(user1);
        uint256 distributorSharesAfter = distributor.getAvailableShares();

        assertEq(user1BVaultSharesAfter, user1SharesBefore, "User should receive destinationVault shares");
        assertEq(
            distributorSharesAfter, distributorSharesBefore - user1SharesBefore, "Distributor shares should decrease"
        );
    }

    function test_claimOnTargetChain_withNoShares() public {
        address noSharesUser = makeAddr("noSharesUser");
        vm.deal(noSharesUser, 1 ether);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        vm.expectRevert(IConcretePredepositVaultImpl.NoSharesToClaim.selector);
        vm.prank(noSharesUser);
        predepositVault.claimOnTargetChain{value: 0.01 ether}(options);
    }

    function test_claimOnTargetChain_insufficientFee() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        // Quote the actual fee required via OApp
        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteClaimOnTargetChain(user1, options, false);

        // Try to send with insufficient fee
        uint256 insufficientFee = fee.nativeFee - 1;

        vm.expectRevert(
            abi.encodeWithSelector(PredepostVaultOApp.InsufficientFee.selector, fee.nativeFee, insufficientFee)
        );
        vm.prank(user1);
        predepositVault.claimOnTargetChain{value: insufficientFee}(options);
    }

    function test_quoteClaimOnTargetChain() public view {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        // Quote via OApp
        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteClaimOnTargetChain(user1, options, false);

        // Fee should be non-zero
        assertGt(fee.nativeFee, 0, "Native fee should be non-zero");
    }

    function test_multipleUsers_canClaim() public {
        uint256 user1Shares = predepositVault.balanceOf(user1);
        uint256 user2Shares = predepositVault.balanceOf(user2);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteClaimOnTargetChain(user1, options, false);

        // User1 claims
        vm.prank(user1);
        predepositVault.claimOnTargetChain{value: fee.nativeFee}(options);

        // Verify packets for user1
        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // User2 claims
        vm.prank(user2);
        predepositVault.claimOnTargetChain{value: fee.nativeFee}(options);

        // Verify packets for user2
        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // Both users should have their shares burned on chain A
        assertEq(predepositVault.balanceOf(user1), 0);
        assertEq(predepositVault.balanceOf(user2), 0);
        assertEq(predepositVault.getLockedShares(user1), user1Shares);
        assertEq(predepositVault.getLockedShares(user2), user2Shares);

        // Both users should have received destinationVault shares on chain B
        assertEq(destinationVault.balanceOf(user1), user1Shares, "User1 should receive destinationVault shares");
        assertEq(destinationVault.balanceOf(user2), user2Shares, "User2 should receive destinationVault shares");
    }

    function test_shareValueCalculation_withYield() public {
        // Add some yield to the vault
        uint256 yieldAmount = 1000e18;
        asset.mint(address(predepositVault), yieldAmount);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteClaimOnTargetChain(user1, options, false);

        uint256 user1Shares = predepositVault.balanceOf(user1);

        vm.expectEmit(true, true, true, true);
        emit SharesClaimedOnTargetChain(user1, user1Shares);

        vm.prank(user1);
        predepositVault.claimOnTargetChain{value: fee.nativeFee}(options);

        // Verify packets sent to distributor
        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // Verify user received shares on destination chain
        assertEq(destinationVault.balanceOf(user1), user1Shares, "User should receive shares on chain B");
    }

    function test_cannotClaimTwice() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteClaimOnTargetChain(user1, options, false);

        // First claim
        vm.prank(user1);
        predepositVault.claimOnTargetChain{value: fee.nativeFee}(options);

        // Verify packets
        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // Second claim should fail (no shares left)
        vm.expectRevert(IConcretePredepositVaultImpl.NoSharesToClaim.selector);
        vm.prank(user1);
        predepositVault.claimOnTargetChain{value: fee.nativeFee}(options);
    }

    function test_claimPreservesLockedSharesAccumulation() public {
        // Use user1's existing shares from setup (no new deposit needed)
        uint256 totalShares = predepositVault.balanceOf(user1);
        uint256 firstBatchShares = totalShares / 2;

        // Transfer half the shares to another address temporarily
        address tempHolder = makeAddr("tempHolder");
        vm.prank(user1);
        predepositVault.transfer(tempHolder, firstBatchShares);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteClaimOnTargetChain(user1, options, false);

        // Claim first batch
        uint256 remainingShares = predepositVault.balanceOf(user1);
        vm.prank(user1);
        predepositVault.claimOnTargetChain{value: fee.nativeFee}(options);

        // Verify packets
        verifyPackets(bEid, addressToBytes32(address(distributor)));

        uint256 firstLockedAmount = predepositVault.getLockedShares(user1);
        assertEq(firstLockedAmount, remainingShares);

        // User should have received first batch on chain B
        assertEq(destinationVault.balanceOf(user1), remainingShares, "User should have received first batch");

        // Transfer shares back
        vm.prank(tempHolder);
        predepositVault.transfer(user1, firstBatchShares);

        // Claim second batch
        vm.prank(user1);
        predepositVault.claimOnTargetChain{value: fee.nativeFee}(options);

        // Verify packets
        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // Locked shares should accumulate on chain A
        uint256 totalLocked = predepositVault.getLockedShares(user1);
        assertEq(totalLocked, remainingShares + firstBatchShares);

        // User should have received total shares on chain B
        assertEq(destinationVault.balanceOf(user1), remainingShares + firstBatchShares, "User should have total shares");
    }

    function test_claimOnTargetChain_revertsWhenDepositsNotLocked() public {
        // Restore deposit limits (unlock deposits)
        vm.prank(vaultManager);
        predepositVault.setDepositLimits(0, type(uint256).max);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteClaimOnTargetChain(user1, options, false);

        // Claim should revert because deposits are not locked
        vm.prank(user1);
        vm.expectRevert(IConcretePredepositVaultImpl.DepositsNotLocked.selector);
        predepositVault.claimOnTargetChain{value: fee.nativeFee}(options);
    }

    // ===== Exchange Rate Invariant Tests =====

    function test_exchangeRate_remainsConstant_duringClaims() public {
        // Get initial exchange rate (price per share in assets)
        uint256 decimals = predepositVault.decimals();
        uint256 oneShare = 10 ** decimals;
        uint256 initialExchangeRate = predepositVault.convertToAssets(oneShare);

        uint256 initialTotalSupply = predepositVault.totalSupply();
        uint256 initialTotalAssets = predepositVault.cachedTotalAssets();

        assertGt(initialTotalSupply, 0, "Should have initial supply");
        assertGt(initialTotalAssets, 0, "Should have initial assets");

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteClaimOnTargetChain(user1, options, false);

        // User1 claims
        vm.prank(user1);
        predepositVault.claimOnTargetChain{value: fee.nativeFee}(options);
        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // Check exchange rate after first claim
        uint256 exchangeRateAfterClaim1 =
            predepositVault.totalSupply() > 0 ? predepositVault.convertToAssets(oneShare) : 0;

        if (predepositVault.totalSupply() > 0) {
            // Allow for small rounding differences (< 0.01%)
            uint256 diff = exchangeRateAfterClaim1 > initialExchangeRate
                ? exchangeRateAfterClaim1 - initialExchangeRate
                : initialExchangeRate - exchangeRateAfterClaim1;
            uint256 maxDiff = initialExchangeRate / 10000; // 0.01%
            assertLe(diff, maxDiff, "Exchange rate should remain nearly constant after claim 1");
        }

        // User2 claims
        vm.prank(user2);
        predepositVault.claimOnTargetChain{value: fee.nativeFee}(options);
        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // After all claims, totalSupply should be 0
        assertEq(predepositVault.totalSupply(), 0, "Total supply should be 0 after all claims");

        // Total assets should be near zero (allowing for rounding)
        uint256 finalAssets = predepositVault.cachedTotalAssets();
        // Assets should be less than 1% of initial (allowing for rounding in conversion)
        assertLt(finalAssets, initialTotalAssets / 100, "Total assets should be near zero after all claims");
    }

    function test_finalState_afterAllClaims() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());

        // User1 claims
        MessagingFee memory fee1 = oapp.quoteClaimOnTargetChain(user1, options, false);
        vm.prank(user1);
        predepositVault.claimOnTargetChain{value: fee1.nativeFee}(options);
        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // User2 claims (last user)
        MessagingFee memory fee2 = oapp.quoteClaimOnTargetChain(user2, options, false);
        vm.prank(user2);
        predepositVault.claimOnTargetChain{value: fee2.nativeFee}(options);
        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // Verify final state
        assertEq(predepositVault.totalSupply(), 0, "Total supply must be exactly zero");

        // Total assets should be very close to zero (allowing for rounding in proportion calculation)
        uint256 finalAssets = predepositVault.cachedTotalAssets();

        // The rounding should leave minimal dust (less than number of users)
        assertLt(finalAssets, 2, "Total assets should be near zero (minimal rounding dust)");

        // Verify both users received their shares on destination
        assertGt(destinationVault.balanceOf(user1), 0, "User1 should have shares on destination");
        assertGt(destinationVault.balanceOf(user2), 0, "User2 should have shares on destination");
    }

    // ===== Batch Claim Tests =====

    function test_batchClaimOnTargetChain_success() public {
        uint256 user1SharesBefore = predepositVault.balanceOf(user1);
        uint256 user2SharesBefore = predepositVault.balanceOf(user2);
        assertGt(user1SharesBefore, 0, "User1 should have shares");
        assertGt(user2SharesBefore, 0, "User2 should have shares");

        // Check initial state on destination chain
        uint256 distributorSharesBefore = distributor.getAvailableShares();
        assertGt(distributorSharesBefore, 0, "Distributor should have shares");

        // Build options for batch operation
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300000, 0);

        // Prepare batch data
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        bytes memory addressesData = abi.encode(users);

        // Quote the fee via OApp
        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteBatchClaimOnTargetChain(addressesData, options, false);

        // Perform the batch claim operation
        vm.prank(vaultManager);
        predepositVault.batchClaimOnTargetChain{value: fee.nativeFee}(addressesData, options);

        // Verify packets sent to distributor
        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // Check shares are burned on chain A
        assertEq(predepositVault.balanceOf(user1), 0, "User1 shares should be burned");
        assertEq(predepositVault.balanceOf(user2), 0, "User2 shares should be burned");

        // Check locked shares tracking
        assertEq(predepositVault.getLockedShares(user1), user1SharesBefore);
        assertEq(predepositVault.getLockedShares(user2), user2SharesBefore);

        // Check shares distributed on chain B
        assertEq(destinationVault.balanceOf(user1), user1SharesBefore, "User1 should receive shares on chain B");
        assertEq(destinationVault.balanceOf(user2), user2SharesBefore, "User2 should receive shares on chain B");
    }

    function test_batchClaimOnTargetChain_emptyArrayReverts() public {
        address[] memory emptyUsers = new address[](0);
        bytes memory addressesData = abi.encode(emptyUsers);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300000, 0);

        vm.expectRevert(abi.encodeWithSelector(IConcretePredepositVaultImpl.BadAddressArrayLength.selector, 0));
        vm.prank(vaultManager);
        predepositVault.batchClaimOnTargetChain{value: 1 ether}(addressesData, options);
    }

    function test_batchClaimOnTargetChain_maxValidArraySucceeds() public {
        // Create array with exactly 150 users (max allowed)
        address[] memory maxUsers = new address[](150);
        for (uint256 i = 0; i < 150; i++) {
            maxUsers[i] = user1; // All same user is fine for array length validation test
        }
        bytes memory addressesData = abi.encode(maxUsers);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300000, 0);

        // Should NOT revert with BadAddressArrayLength for exactly 150 users
        // The function may fail for other reasons (e.g., insufficient shares),
        // but the array length validation should pass
        vm.prank(vaultManager);
        try predepositVault.batchClaimOnTargetChain{value: 1 ether}(addressesData, options) {
        // If it succeeds, great - the validation passed
        }
        catch (bytes memory reason) {
            // If it fails, ensure it's NOT due to BadAddressArrayLength
            bytes4 selector = bytes4(reason);
            assertNotEq(
                selector,
                IConcretePredepositVaultImpl.BadAddressArrayLength.selector,
                "Should not revert with BadAddressArrayLength for 150 users"
            );
        }
    }

    function test_batchClaimOnTargetChain_slightlyOverLimitReverts() public {
        address[] memory tooManyUsers = new address[](151);
        for (uint256 i = 0; i < 151; i++) {
            tooManyUsers[i] = makeAddr(string(abi.encodePacked("user", i)));
        }
        bytes memory addressesData = abi.encode(tooManyUsers);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300000, 0);

        vm.expectRevert(abi.encodeWithSelector(IConcretePredepositVaultImpl.BadAddressArrayLength.selector, 151));
        vm.prank(vaultManager);
        predepositVault.batchClaimOnTargetChain{value: 1 ether}(addressesData, options);
    }

    function test_batchClaimOnTargetChain_muchLargerArrayReverts() public {
        address[] memory tooManyUsers = new address[](200);
        for (uint256 i = 0; i < 200; i++) {
            tooManyUsers[i] = makeAddr(string(abi.encodePacked("user", i)));
        }
        bytes memory addressesData = abi.encode(tooManyUsers);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300000, 0);

        vm.expectRevert(abi.encodeWithSelector(IConcretePredepositVaultImpl.BadAddressArrayLength.selector, 200));
        vm.prank(vaultManager);
        predepositVault.batchClaimOnTargetChain{value: 1 ether}(addressesData, options);
    }

    function test_batchClaimOnTargetChain_insufficientFee() public {
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        bytes memory addressesData = abi.encode(users);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300000, 0);

        // Quote the actual fee required via OApp
        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteBatchClaimOnTargetChain(addressesData, options, false);

        // Try to send with insufficient fee
        uint256 insufficientFee = fee.nativeFee - 1;

        vm.expectRevert(
            abi.encodeWithSelector(PredepostVaultOApp.InsufficientFee.selector, fee.nativeFee, insufficientFee)
        );
        vm.prank(vaultManager);
        predepositVault.batchClaimOnTargetChain{value: insufficientFee}(addressesData, options);
    }

    function test_batchClaimOnTargetChain_onlyVaultManager() public {
        address[] memory users = new address[](1);
        users[0] = user1;
        bytes memory addressesData = abi.encode(users);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300000, 0);

        // Try with non-manager
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, RolesLib.VAULT_MANAGER
            )
        );
        vm.prank(user1);
        predepositVault.batchClaimOnTargetChain{value: 1 ether}(addressesData, options);

        // Should work with vault manager via OApp
        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteBatchClaimOnTargetChain(addressesData, options, false);
        vm.prank(vaultManager);
        predepositVault.batchClaimOnTargetChain{value: fee.nativeFee}(addressesData, options);
    }

    function test_batchClaimOnTargetChain_revertsWhenDepositsNotLocked() public {
        // Restore deposit limits (unlock deposits)
        vm.prank(vaultManager);
        predepositVault.setDepositLimits(0, type(uint256).max);

        address[] memory users = new address[](1);
        users[0] = user1;
        bytes memory addressesData = abi.encode(users);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300000, 0);

        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteBatchClaimOnTargetChain(addressesData, options, false);

        // Batch claim should revert because deposits are not locked
        vm.prank(vaultManager);
        vm.expectRevert(IConcretePredepositVaultImpl.DepositsNotLocked.selector);
        predepositVault.batchClaimOnTargetChain{value: fee.nativeFee}(addressesData, options);
    }

    function test_batchClaimOnTargetChain_skipsUsersWithNoShares() public {
        address noSharesUser = makeAddr("noSharesUser");

        // Create array with users, including one with no shares
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = noSharesUser; // Has no shares
        users[2] = user2;
        bytes memory addressesData = abi.encode(users);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300000, 0);

        uint256 user1SharesBefore = predepositVault.balanceOf(user1);
        uint256 user2SharesBefore = predepositVault.balanceOf(user2);

        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteBatchClaimOnTargetChain(addressesData, options, false);

        // Batch claim should succeed and skip the user with no shares
        vm.prank(vaultManager);
        predepositVault.batchClaimOnTargetChain{value: fee.nativeFee}(addressesData, options);

        // Verify packets sent
        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // Only user1 and user2 should have shares distributed
        assertEq(destinationVault.balanceOf(user1), user1SharesBefore);
        assertEq(destinationVault.balanceOf(user2), user2SharesBefore);
        assertEq(destinationVault.balanceOf(noSharesUser), 0, "User with no shares should not receive any");
    }

    function test_batchClaimOnTargetChain_handlesDuplicateUsers() public {
        // Create array with duplicate users
        address[] memory users = new address[](4);
        users[0] = user1;
        users[1] = user2;
        users[2] = user1; // Duplicate of user1
        users[3] = user2; // Duplicate of user2
        bytes memory addressesData = abi.encode(users);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300000, 0);

        uint256 user1SharesBefore = predepositVault.balanceOf(user1);
        uint256 user2SharesBefore = predepositVault.balanceOf(user2);

        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteBatchClaimOnTargetChain(addressesData, options, false);

        // Batch claim should succeed - duplicates are skipped (0 shares on second occurrence)
        vm.prank(vaultManager);
        predepositVault.batchClaimOnTargetChain{value: fee.nativeFee}(addressesData, options);

        // Verify packets sent
        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // Both users should have their shares burned on chain A (only once)
        assertEq(predepositVault.balanceOf(user1), 0, "User1 shares should be burned");
        assertEq(predepositVault.balanceOf(user2), 0, "User2 shares should be burned");

        // Users should receive shares on chain B (only the original amount, not doubled)
        assertEq(destinationVault.balanceOf(user1), user1SharesBefore, "User1 should receive shares only once");
        assertEq(destinationVault.balanceOf(user2), user2SharesBefore, "User2 should receive shares only once");
    }

    function test_quoteBatchClaimOnTargetChain() public view {
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        bytes memory addressesData = abi.encode(users);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300000, 0);

        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteBatchClaimOnTargetChain(addressesData, options, false);

        // Fee should be non-zero
        assertGt(fee.nativeFee, 0, "Native fee should be non-zero");
    }

    function test_batchClaim_exchangeRate_remainsConstant() public {
        // Prepare batch claim
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        bytes memory addressesData = abi.encode(users);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300000, 0);

        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteBatchClaimOnTargetChain(addressesData, options, false);

        // Execute batch claim
        vm.prank(vaultManager);
        predepositVault.batchClaimOnTargetChain{value: fee.nativeFee}(addressesData, options);
        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // After batch claim all users should be done
        assertEq(predepositVault.totalSupply(), 0, "Total supply should be 0");

        // Assets should be near zero
        uint256 finalAssets = predepositVault.cachedTotalAssets();
        assertLt(finalAssets, 2, "Total assets should be near zero");
    }

    // ===== Fuzz Tests =====

    /// @notice Fuzz test for N users depositing and claiming sequentially
    /// @dev Tests that exchange rate remains constant and final state is correct for any number of users
    /// @param seed Random seed for generating deposit amounts
    /// @param numUsers Number of users to test (bounded between 2 and 10)
    function testFuzz_nUsersClaim_finalStateCorrect(uint256 seed, uint8 numUsers) public {
        // Bound number of users (2-10 to keep test execution reasonable)
        numUsers = uint8(bound(numUsers, 2, 10));

        // Clear existing setup - remove user1 and user2 shares from base setup
        _clearExistingUsers();

        // Unlock deposits temporarily for fuzz test setup
        vm.prank(vaultManager);
        predepositVault.setDepositLimits(0, type(uint256).max);

        // Setup: create users and deposits
        (address[] memory fuzzUsers, uint256 initialTotalSupply) = _setupFuzzUsers(seed, numUsers);

        // Allocate all assets to strategy and lock deposits
        _allocateAndLock();

        // Record initial exchange rate
        uint256 initialExchangeRate = predepositVault.convertToAssets(10 ** predepositVault.decimals());

        // Execute claims and verify state
        _executeFuzzClaims(fuzzUsers, numUsers, initialExchangeRate);

        // Verify final state
        _verifyFuzzFinalState(fuzzUsers, numUsers, initialTotalSupply);
    }

    /// @dev Helper to clear existing users from base setup
    function _clearExistingUsers() internal {
        // Unlock withdrawals first (they're locked in base setup)
        vm.prank(vaultManager);
        predepositVault.setWithdrawLimits(0, type(uint256).max);

        // Deallocate assets from strategy if needed
        uint256 strategyBalance = strategy.totalAllocatedValue();
        if (strategyBalance > 0) {
            IAllocateModule.AllocateParams[] memory params = new IAllocateModule.AllocateParams[](1);
            params[0] = IAllocateModule.AllocateParams({
                isDeposit: false, strategy: address(strategy), extraData: abi.encode(strategyBalance)
            });
            vm.prank(allocator);
            predepositVault.allocate(abi.encode(params));
        }

        // Withdraw all shares for user1 and user2 if they have any
        uint256 user1Shares = predepositVault.balanceOf(user1);
        uint256 user2Shares = predepositVault.balanceOf(user2);

        if (user1Shares > 0) {
            vm.prank(user1);
            predepositVault.redeem(user1Shares, user1, user1);
        }

        if (user2Shares > 0) {
            vm.prank(user2);
            predepositVault.redeem(user2Shares, user2, user2);
        }
    }

    /// @dev Helper to setup fuzz test users and deposits
    function _setupFuzzUsers(uint256 seed, uint8 numUsers) internal returns (address[] memory, uint256) {
        address[] memory fuzzUsers = new address[](numUsers);

        unchecked {
            for (uint8 i = 0; i < numUsers; i++) {
                fuzzUsers[i] = address(uint160(uint256(keccak256(abi.encodePacked("fuzzUser", i, seed)))));
                uint256 depositAmount = bound(uint256(keccak256(abi.encodePacked(seed, i))), 100e18, 10000e18);

                asset.mint(fuzzUsers[i], depositAmount);
                vm.prank(fuzzUsers[i]);
                asset.approve(address(predepositVault), depositAmount);
                vm.deal(fuzzUsers[i], 1 ether);

                vm.prank(fuzzUsers[i]);
                predepositVault.deposit(depositAmount, fuzzUsers[i]);
            }
        }

        return (fuzzUsers, predepositVault.totalSupply());
    }

    /// @dev Helper to allocate assets and lock deposits/withdrawals
    function _allocateAndLock() internal {
        uint256 totalDeposited = predepositVault.cachedTotalAssets();
        IAllocateModule.AllocateParams[] memory params = new IAllocateModule.AllocateParams[](1);
        params[0] = IAllocateModule.AllocateParams({
            isDeposit: true, strategy: address(strategy), extraData: abi.encode(totalDeposited)
        });
        vm.prank(allocator);
        predepositVault.allocate(abi.encode(params));

        vm.startPrank(vaultManager);
        predepositVault.setDepositLimits(0, 0);
        predepositVault.setWithdrawLimits(0, 0);
        vm.stopPrank();
    }

    /// @dev Helper to execute fuzz test claims with exchange rate validation
    function _executeFuzzClaims(address[] memory fuzzUsers, uint8 numUsers, uint256 initialExchangeRate) internal {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        uint256 oneShare = 10 ** predepositVault.decimals();

        unchecked {
            for (uint8 i = 0; i < numUsers; i++) {
                // Validate exchange rate BEFORE claim
                if (predepositVault.totalSupply() > 0) {
                    uint256 rateBefore = predepositVault.convertToAssets(oneShare);
                    uint256 diffBefore = rateBefore > initialExchangeRate
                        ? rateBefore - initialExchangeRate
                        : initialExchangeRate - rateBefore;
                    assertLe(
                        diffBefore, initialExchangeRate / 1000, "Exchange rate should remain constant before claim"
                    );
                }

                // Execute claim
                MessagingFee memory fee = oapp.quoteClaimOnTargetChain(fuzzUsers[i], options, false);

                vm.prank(fuzzUsers[i]);
                predepositVault.claimOnTargetChain{value: fee.nativeFee}(options);

                verifyPackets(bEid, addressToBytes32(address(distributor)));

                // Validate exchange rate AFTER claim (if there are remaining shares)
                if (predepositVault.totalSupply() > 0) {
                    uint256 rateAfter = predepositVault.convertToAssets(oneShare);
                    uint256 diffAfter = rateAfter > initialExchangeRate
                        ? rateAfter - initialExchangeRate
                        : initialExchangeRate - rateAfter;
                    assertLe(diffAfter, initialExchangeRate / 1000, "Exchange rate should remain constant after claim");
                }
            }
        }
    }

    /// @dev Helper to verify fuzz test final state
    function _verifyFuzzFinalState(address[] memory fuzzUsers, uint8 numUsers, uint256 initialTotalSupply)
        internal
        view
    {
        assertEq(predepositVault.totalSupply(), 0, "Total supply must be exactly zero");
        assertLt(predepositVault.cachedTotalAssets(), numUsers, "Total assets should be near zero");

        uint256 totalDestinationShares = 0;
        unchecked {
            for (uint8 i = 0; i < numUsers; i++) {
                totalDestinationShares += destinationVault.balanceOf(fuzzUsers[i]);
            }
        }
        assertEq(totalDestinationShares, initialTotalSupply, "Total destination shares should equal initial supply");
    }
}
