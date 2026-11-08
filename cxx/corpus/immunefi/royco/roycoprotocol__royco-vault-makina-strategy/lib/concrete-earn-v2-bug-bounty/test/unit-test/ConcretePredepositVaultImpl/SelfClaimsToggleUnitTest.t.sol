// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ConcretePredepositVaultImplBaseSetup} from "../../common/ConcretePredepositVaultImplBaseSetup.t.sol";
import {ConcretePredepositVaultImpl} from "../../../src/implementation/ConcretePredepositVaultImpl.sol";
import {IConcretePredepositVaultImpl} from "../../../src/interface/IConcretePredepositVaultImpl.sol";
import {IPredepostVaultOApp} from "../../../src/periphery/interface/IPredepostVaultOApp.sol";
import {MessagingFee} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {ERC4626StrategyMock} from "../../mock/ERC4626StrategyMock.sol";
import {IAllocateModule} from "../../../src/interface/IAllocateModule.sol";
import {IAccessControl} from "@openzeppelin-contracts/access/IAccessControl.sol";
import {ConcreteV2RolesLib as RolesLib} from "../../../src/lib/Roles.sol";

contract SelfClaimsToggleUnitTest is ConcretePredepositVaultImplBaseSetup {
    using OptionsBuilder for bytes;

    address public user1;
    address public user2;

    ERC4626StrategyMock public strategy;

    event SelfClaimsEnabledUpdated(bool enabled);

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
        vm.deal(vaultManager, 10 ether);

        // Approve vault
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

        // Users deposit into vault
        vm.prank(user1);
        predepositVault.deposit(5000e18, user1);

        vm.prank(user2);
        predepositVault.deposit(3000e18, user2);

        // Disable self claims initially (default from base setup)
        vm.prank(vaultManager);
        predepositVault.setSelfClaimsEnabled(false);

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

    function test_initialSelfClaimsState() public view {
        // In this test, self claims are disabled in setUp (initialized as true, then toggled to false)
        assertFalse(predepositVault.getSelfClaimsEnabled(), "Self claims should be disabled in this test setup");
    }

    function test_setSelfClaimsEnabled_onlyVaultManager() public {
        // Non-vault manager should not be able to set self claims
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, RolesLib.VAULT_MANAGER
            )
        );
        vm.prank(user1);
        predepositVault.setSelfClaimsEnabled(true);

        // Vault manager should be able to enable self claims
        vm.expectEmit(true, true, true, true);
        emit SelfClaimsEnabledUpdated(true);

        vm.prank(vaultManager);
        predepositVault.setSelfClaimsEnabled(true);

        assertTrue(predepositVault.getSelfClaimsEnabled(), "Self claims should be enabled");
    }

    function test_claimOnTargetChain_whenSelfClaimsDisabled() public {
        // Self claims are disabled in this test setup
        assertFalse(predepositVault.getSelfClaimsEnabled());

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteClaimOnTargetChain(user1, options, false);

        // User should not be able to claim when self claims are disabled
        vm.expectRevert(IConcretePredepositVaultImpl.SelfClaimsDisabled.selector);
        vm.prank(user1);
        predepositVault.claimOnTargetChain{value: fee.nativeFee}(options);
    }

    function test_claimOnTargetChain_whenSelfClaimsEnabled() public {
        // Enable self claims
        vm.prank(vaultManager);
        predepositVault.setSelfClaimsEnabled(true);

        assertTrue(predepositVault.getSelfClaimsEnabled());

        uint256 user1SharesBefore = predepositVault.balanceOf(user1);
        assertGt(user1SharesBefore, 0, "User should have shares");

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteClaimOnTargetChain(user1, options, false);

        // User should be able to claim when self claims are enabled
        vm.prank(user1);
        predepositVault.claimOnTargetChain{value: fee.nativeFee}(options);

        // Verify packets sent
        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // Verify shares were burned
        assertEq(predepositVault.balanceOf(user1), 0, "User shares should be burned");
        assertEq(predepositVault.getLockedShares(user1), user1SharesBefore, "Locked shares should be tracked");

        // Verify shares received on destination chain
        assertEq(
            destinationVault.balanceOf(user1), user1SharesBefore, "User should receive shares on destination chain"
        );
    }

    function test_toggleSelfClaims_multipleUsers() public {
        // Self claims are disabled in this test setup
        assertFalse(predepositVault.getSelfClaimsEnabled());

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        // User1 cannot claim
        vm.expectRevert(IConcretePredepositVaultImpl.SelfClaimsDisabled.selector);
        vm.prank(user1);
        predepositVault.claimOnTargetChain{value: 0.01 ether}(options);

        // Enable self claims
        vm.prank(vaultManager);
        predepositVault.setSelfClaimsEnabled(true);

        // Now user1 can claim
        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteClaimOnTargetChain(user1, options, false);
        vm.prank(user1);
        predepositVault.claimOnTargetChain{value: fee.nativeFee}(options);

        verifyPackets(bEid, addressToBytes32(address(distributor)));
        assertEq(predepositVault.balanceOf(user1), 0, "User1 shares should be burned");

        // Disable self claims again
        vm.prank(vaultManager);
        predepositVault.setSelfClaimsEnabled(false);

        // User2 cannot claim now
        vm.expectRevert(IConcretePredepositVaultImpl.SelfClaimsDisabled.selector);
        vm.prank(user2);
        predepositVault.claimOnTargetChain{value: fee.nativeFee}(options);
    }

    function test_batchClaimWorksRegardlessOfSelfClaimsState() public {
        // Self claims are disabled in this test setup
        assertFalse(predepositVault.getSelfClaimsEnabled());

        // Batch claim should still work (vault manager can always do batch claims)
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        bytes memory addressesData = abi.encode(users);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300000, 0);

        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteBatchClaimOnTargetChain(addressesData, options, false);

        vm.prank(vaultManager);
        predepositVault.batchClaimOnTargetChain{value: fee.nativeFee}(addressesData, options);

        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // Verify shares were processed
        assertEq(predepositVault.balanceOf(user1), 0, "User1 shares should be burned");
        assertEq(predepositVault.balanceOf(user2), 0, "User2 shares should be burned");
    }

    function test_setSelfClaimsEnabled_emitsEvent() public {
        // Enable self claims
        vm.expectEmit(true, true, true, true);
        emit SelfClaimsEnabledUpdated(true);
        vm.prank(vaultManager);
        predepositVault.setSelfClaimsEnabled(true);

        // Disable self claims
        vm.expectEmit(true, true, true, true);
        emit SelfClaimsEnabledUpdated(false);
        vm.prank(vaultManager);
        predepositVault.setSelfClaimsEnabled(false);
    }

    function test_setSelfClaimsEnabled_idempotent() public {
        // Enable multiple times
        vm.startPrank(vaultManager);
        predepositVault.setSelfClaimsEnabled(true);
        assertTrue(predepositVault.getSelfClaimsEnabled());

        predepositVault.setSelfClaimsEnabled(true);
        assertTrue(predepositVault.getSelfClaimsEnabled());

        // Disable multiple times
        predepositVault.setSelfClaimsEnabled(false);
        assertFalse(predepositVault.getSelfClaimsEnabled());

        predepositVault.setSelfClaimsEnabled(false);
        assertFalse(predepositVault.getSelfClaimsEnabled());
        vm.stopPrank();
    }

    function test_getSelfClaimsEnabled_returnsCorrectState() public {
        // Initially false in this test setup
        assertFalse(predepositVault.getSelfClaimsEnabled());

        // After enabling
        vm.prank(vaultManager);
        predepositVault.setSelfClaimsEnabled(true);
        assertTrue(predepositVault.getSelfClaimsEnabled());

        // After disabling
        vm.prank(vaultManager);
        predepositVault.setSelfClaimsEnabled(false);
        assertFalse(predepositVault.getSelfClaimsEnabled());
    }

    function test_initializationDefaultsSelfClaimsDisabled() public {
        // Deploy a new vault - selfClaimsEnabled should default to false
        ConcretePredepositVaultImpl newVault = ConcretePredepositVaultImpl(
            factory.create(
                2, vaultOwner, abi.encode(address(allocateModule), address(asset), vaultManager, "Test Vault", "TV")
            )
        );

        // Verify self claims are disabled by default from initialization
        assertFalse(newVault.getSelfClaimsEnabled(), "Self claims should be disabled by default");

        // Can be enabled via setter
        vm.prank(vaultManager);
        newVault.setSelfClaimsEnabled(true);
        assertTrue(newVault.getSelfClaimsEnabled(), "Self claims should be enabled after setter call");
    }
}
