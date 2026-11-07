// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ConcretePredepositVaultImplBaseSetup} from "../../common/ConcretePredepositVaultImplBaseSetup.t.sol";
import {ConcretePredepositVaultImpl} from "../../../src/implementation/ConcretePredepositVaultImpl.sol";
import {ConcreteStandardVaultImpl} from "../../../src/implementation/ConcreteStandardVaultImpl.sol";
import {IPredepostVaultOApp} from "../../../src/periphery/interface/IPredepostVaultOApp.sol";
import {PredepostVaultOApp} from "../../../src/periphery/predeposit/PredepostVaultOApp.sol";
import {IConcretePredepositVaultImpl} from "../../../src/interface/IConcretePredepositVaultImpl.sol";
import {IConcreteStandardVaultImpl} from "../../../src/interface/IConcreteStandardVaultImpl.sol";
import {MessagingFee} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {ERC4626StrategyMock} from "../../mock/ERC4626StrategyMock.sol";
import {IAllocateModule} from "../../../src/interface/IAllocateModule.sol";
import {ConcreteV2RolesLib as RolesLib} from "../../../src/lib/Roles.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {console} from "forge-std/console.sol";

contract UpgradeToPredeposit is ConcretePredepositVaultImplBaseSetup {
    using OptionsBuilder for bytes;

    address public user1;
    address public user2;

    ConcreteStandardVaultImpl public standardVault;
    ERC4626StrategyMock public strategy;

    function setUp() public override {
        super.setUp();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Set migratable path from version 1 (standard) to version 2 (predeposit)
        vm.prank(factoryOwner);
        factory.setMigratable(1, 2);

        // Fund user accounts with assets
        asset.mint(user1, 10000e18);
        asset.mint(user2, 10000e18);

        // Fund users with ETH for LayerZero fees
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(vaultManager, 10 ether);

        // Deploy a standard vault (version 1)
        standardVault = ConcreteStandardVaultImpl(
            factory.create(
                1, // Version 1 - ConcreteStandardVaultImpl
                vaultOwner,
                abi.encode(address(allocateModule), address(asset), vaultManager, "Standard Vault to Upgrade", "SVTU")
            )
        );

        // Setup roles for standard vault
        vm.startPrank(vaultManager);
        standardVault.grantRole(RolesLib.STRATEGY_MANAGER, strategyOperator);
        standardVault.grantRole(RolesLib.ALLOCATOR, allocator);
        standardVault.grantRole(RolesLib.HOOK_MANAGER, hookManager);
        vm.stopPrank();

        // Approve vault for users
        vm.prank(user1);
        asset.approve(address(standardVault), 10000e18);

        vm.prank(user2);
        asset.approve(address(standardVault), 10000e18);

        // Deploy and setup strategy
        strategy = new ERC4626StrategyMock(address(asset));
        vm.prank(strategyOperator);
        standardVault.addStrategy(address(strategy));

        // Add strategy to deallocation order
        address[] memory order = new address[](1);
        order[0] = address(strategy);
        vm.prank(allocator);
        standardVault.setDeallocationOrder(order);

        // Users deposit into standard vault
        vm.prank(user1);
        standardVault.deposit(5000e18, user1);

        vm.prank(user2);
        standardVault.deposit(3000e18, user2);
    }

    function test_upgradeStandardVaultToPredeposit() public {
        // Verify initial state as standard vault
        uint256 user1SharesBefore = standardVault.balanceOf(user1);
        uint256 user2SharesBefore = standardVault.balanceOf(user2);
        uint256 totalAssetsBefore = standardVault.totalAssets();

        assertGt(user1SharesBefore, 0, "User1 should have shares before upgrade");
        assertGt(user2SharesBefore, 0, "User2 should have shares before upgrade");
        assertGt(totalAssetsBefore, 0, "Vault should have assets before upgrade");

        // Verify it's currently a standard vault (should not have predeposit functions)
        // Try to call predeposit-specific function - should fail
        vm.expectRevert();
        ConcretePredepositVaultImpl(address(standardVault)).getOApp();

        // Upgrade to predeposit vault (version 2) through factory
        // No upgrade data needed - selfClaimsEnabled defaults to false
        bytes memory upgradeData = "";

        vm.prank(vaultOwner);
        factory.upgrade(address(standardVault), 2, upgradeData);

        // Now cast to predeposit vault interface
        ConcretePredepositVaultImpl predepositVault = ConcretePredepositVaultImpl(address(standardVault));

        // Deploy and set up OApp for the upgraded vault
        address lzEndpointA = address(endpoints[aEid]);
        PredepostVaultOApp oappImpl = new PredepostVaultOApp(lzEndpointA);
        bytes memory oappInitData =
            abi.encodeCall(PredepostVaultOApp.initialize, (address(predepositVault), vaultOwner));
        ERC1967Proxy oappProxy = new ERC1967Proxy(address(oappImpl), oappInitData);
        PredepostVaultOApp oapp = PredepostVaultOApp(address(oappProxy));

        vm.prank(vaultManager);
        predepositVault.setOApp(address(oapp));

        // Configure OApp
        vm.startPrank(vaultOwner);
        oapp.setDstEid(bEid);
        oapp.setPeer(bEid, addressToBytes32(address(distributor)));
        vm.stopPrank();

        // Verify state is preserved after upgrade
        assertEq(predepositVault.balanceOf(user1), user1SharesBefore, "User1 shares should be preserved");
        assertEq(predepositVault.balanceOf(user2), user2SharesBefore, "User2 shares should be preserved");
        assertEq(predepositVault.totalAssets(), totalAssetsBefore, "Total assets should be preserved");

        // Verify standard vault functionality still works
        assertEq(predepositVault.asset(), address(asset), "Asset should be the same");
        assertEq(predepositVault.name(), "Standard Vault to Upgrade", "Name should be preserved");
        assertEq(predepositVault.symbol(), "SVTU", "Symbol should be preserved");

        // Verify new predeposit functionality is available
        assertEq(oapp.dstEid(), bEid, "DstEid should be set on OApp");
        assertFalse(predepositVault.getSelfClaimsEnabled(), "Self claims should be disabled by default on upgrade");

        // Test toggling self claims (new predeposit function)
        vm.prank(vaultManager);
        predepositVault.setSelfClaimsEnabled(true);
        assertTrue(predepositVault.getSelfClaimsEnabled(), "Self claims should be enabled");

        // Verify roles are preserved
        assertTrue(
            predepositVault.hasRole(RolesLib.VAULT_MANAGER, vaultManager), "Vault manager role should be preserved"
        );
        assertTrue(
            predepositVault.hasRole(RolesLib.STRATEGY_MANAGER, strategyOperator),
            "Strategy manager role should be preserved"
        );
        assertTrue(predepositVault.hasRole(RolesLib.ALLOCATOR, allocator), "Allocator role should be preserved");
    }

    function test_upgradeAndUsePredeposiFeatures() public {
        // Upgrade to predeposit vault through factory
        // No upgrade data needed - selfClaimsEnabled defaults to false
        bytes memory upgradeData = "";

        vm.prank(vaultOwner);
        factory.upgrade(address(standardVault), 2, upgradeData);

        ConcretePredepositVaultImpl predepositVault = ConcretePredepositVaultImpl(address(standardVault));

        // Deploy and set up OApp for the upgraded vault
        address lzEndpointA = address(endpoints[aEid]);
        PredepostVaultOApp oappImpl = new PredepostVaultOApp(lzEndpointA);
        bytes memory oappInitData =
            abi.encodeCall(PredepostVaultOApp.initialize, (address(predepositVault), vaultOwner));
        ERC1967Proxy oappProxy = new ERC1967Proxy(address(oappImpl), oappInitData);
        PredepostVaultOApp oapp = PredepostVaultOApp(address(oappProxy));

        vm.prank(vaultManager);
        predepositVault.setOApp(address(oapp));

        // Verify predeposit-specific functions are accessible and work

        // Test setDstEid on OApp
        vm.prank(vaultOwner);
        oapp.setDstEid(bEid);
        assertEq(oapp.dstEid(), bEid, "DstEid should be set on OApp");

        // Test setSelfClaimsEnabled - should be disabled by default after upgrade
        assertFalse(predepositVault.getSelfClaimsEnabled(), "Self claims should be disabled by default after upgrade");

        vm.prank(vaultManager);
        predepositVault.setSelfClaimsEnabled(true);
        assertTrue(predepositVault.getSelfClaimsEnabled(), "Self claims should be enabled");

        vm.prank(vaultManager);
        predepositVault.setSelfClaimsEnabled(false);
        assertFalse(predepositVault.getSelfClaimsEnabled(), "Self claims should be disabled again");

        // Test getLockedShares (should be 0 initially)
        assertEq(predepositVault.getLockedShares(user1), 0, "Locked shares should be 0 initially");
        assertEq(predepositVault.getLockedShares(user2), 0, "Locked shares should be 0 initially");

        // Test getOApp
        assertEq(predepositVault.getOApp(), address(oapp), "OApp should be set correctly");

        // Test setPeer on the OApp (LayerZero OApp function - requires owner)
        vm.prank(vaultOwner);
        oapp.setPeer(bEid, addressToBytes32(address(distributor)));
        assertEq(oapp.peers(bEid), addressToBytes32(address(distributor)), "Peer should be set correctly on OApp");

        // Test quoting functionality via OApp
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        MessagingFee memory fee = oapp.quoteClaimOnTargetChain(user1, options, false);
        assertGt(fee.nativeFee, 0, "Fee should be non-zero");
    }

    function test_upgradePreservesDepositsAndWithdrawals() public {
        // Record initial state
        uint256 user1AssetsBefore = asset.balanceOf(user1);
        uint256 user1SharesBefore = standardVault.balanceOf(user1);

        // Upgrade to predeposit vault through factory
        bytes memory upgradeData = "";

        vm.prank(vaultOwner);
        factory.upgrade(address(standardVault), 2, upgradeData);

        ConcretePredepositVaultImpl predepositVault = ConcretePredepositVaultImpl(address(standardVault));

        // Test deposits still work after upgrade
        vm.prank(user1);
        uint256 depositAmount = 1000e18;
        uint256 sharesReceived = predepositVault.deposit(depositAmount, user1);

        assertGt(sharesReceived, 0, "Should receive shares from deposit");
        assertEq(
            predepositVault.balanceOf(user1), user1SharesBefore + sharesReceived, "Shares should increase after deposit"
        );

        // Test withdrawals still work after upgrade
        vm.prank(user1);
        uint256 withdrawAmount = 500e18;
        uint256 sharesBurned = predepositVault.withdraw(withdrawAmount, user1, user1);

        assertGt(sharesBurned, 0, "Should burn shares from withdrawal");
        assertEq(
            asset.balanceOf(user1),
            user1AssetsBefore - depositAmount + withdrawAmount,
            "Assets should be correct after deposit and withdrawal"
        );
    }

    function test_upgradePreservesStrategyFunctionality() public {
        // Upgrade to predeposit vault through factory
        bytes memory upgradeData = "";

        vm.prank(vaultOwner);
        factory.upgrade(address(standardVault), 2, upgradeData);

        ConcretePredepositVaultImpl predepositVault = ConcretePredepositVaultImpl(address(standardVault));

        // Verify strategy is still registered
        address[] memory strategies = predepositVault.getStrategies();
        assertEq(strategies.length, 1, "Should have one strategy");
        assertEq(strategies[0], address(strategy), "Strategy should be preserved");

        // Test allocation still works
        uint256 cachedBefore = predepositVault.cachedTotalAssets();
        assertGt(cachedBefore, 0, "Should have assets to allocate");

        IAllocateModule.AllocateParams[] memory params = new IAllocateModule.AllocateParams[](1);
        params[0] = IAllocateModule.AllocateParams({
            isDeposit: true, strategy: address(strategy), extraData: abi.encode(cachedBefore)
        });

        vm.prank(allocator);
        predepositVault.allocate(abi.encode(params));

        // Accrue yield to update cached values (selfClaimsEnabled is false by default after upgrade)
        predepositVault.accrueYield();

        // Verify allocation worked - assets should still be tracked since they're in the strategy
        assertEq(predepositVault.cachedTotalAssets(), cachedBefore, "Total assets should be tracked in strategy");
        assertGt(strategy.totalAllocatedValue(), 0, "Strategy should have received assets");
        assertEq(strategy.totalAllocatedValue(), cachedBefore, "Strategy should have all allocated assets");
    }

    function test_cannotUpgradeToInvalidVersion() public {
        // Try to upgrade to a non-existent version through factory
        bytes memory upgradeData = "";

        vm.expectRevert();
        vm.prank(vaultOwner);
        factory.upgrade(address(standardVault), 999, upgradeData);
    }

    function test_upgradeRequiresOwner() public {
        bytes memory upgradeData = "";

        // Non-owner cannot upgrade through factory
        vm.expectRevert();
        vm.prank(user1);
        factory.upgrade(address(standardVault), 2, upgradeData);

        // Owner can upgrade through factory
        vm.prank(vaultOwner);
        factory.upgrade(address(standardVault), 2, upgradeData);
    }
}
