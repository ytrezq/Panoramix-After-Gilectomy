// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {
    IConcreteFactory,
    ConcreteFactoryBaseSetup,
    VaultProxy,
    IConcreteStandardVaultImpl,
    ConcreteStandardVaultImpl,
    TestBaseSetup
} from "../common/TestBaseSetup.t.sol";
import {ConcretePredepositVaultImpl} from "../../src/implementation/ConcretePredepositVaultImpl.sol";
import {IConcretePredepositVaultImpl} from "../../src/interface/IConcretePredepositVaultImpl.sol";
import {PredepostVaultOApp} from "../../src/periphery/predeposit/PredepostVaultOApp.sol";
import {ShareDistributor} from "../../src/periphery/predeposit/ShareDistributor.sol";
import {ERC20Mock} from "../mock/ERC20Mock.sol";
import {AllocateModule} from "../../src/module/AllocateModule.sol";
import {IAllocateModule} from "../../src/interface/IAllocateModule.sol";
import {ConcreteV2RolesLib as RolesLib} from "../../src/lib/Roles.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MessagingFee} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {IPredepostVaultOApp} from "../../src/periphery/interface/IPredepostVaultOApp.sol";
import {ERC4626StrategyMock} from "../mock/ERC4626StrategyMock.sol";

/**
 * @title LayerZeroClaimE2ETest
 * @notice End-to-end tests for LayerZero cross-chain share claiming using actual ShareDistributor proxy
 * @dev This test suite uses the real ShareDistributor contract (not a mock) to test the complete flow
 */
contract LayerZeroClaimE2ETest is TestBaseSetup, TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 public aEid = 1; // Source chain (where users deposit)
    uint32 public bEid = 2; // Destination chain (where shares are claimed)

    address public vaultOwner;
    address public vaultManager;
    address public strategyOperator;
    address public allocator;
    address public user1;
    address public user2;
    address public user3;

    ERC20Mock public asset;
    AllocateModule public allocateModule;
    ConcretePredepositVaultImpl public predepositVault; // Predeposit vault on chain A (source)
    PredepostVaultOApp public predepositVaultOApp; // OApp for predeposit vault
    ConcreteStandardVaultImpl public destinationVault; // Standard vault on chain B (destination)
    ShareDistributor public distributor; // Real ShareDistributor on chain B
    ERC4626StrategyMock public strategy;

    event SharesClaimedOnTargetChain(address indexed user, uint256 shares);

    function setUp() public virtual override(TestBaseSetup, TestHelperOz5) {
        TestBaseSetup.setUp();
        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        _setupAddresses();
        _deployContracts();
        _setupLabels();
        _configureConnections();
        _setupRoles();
        _setupUsers();
        _fundDistributor();
    }

    function _setupAddresses() private {
        vaultOwner = makeAddr("vaultOwner");
        vaultManager = makeAddr("vaultManager");
        strategyOperator = makeAddr("strategyOperator");
        allocator = makeAddr("allocator");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
    }

    function _deployContracts() private {
        asset = new ERC20Mock();
        allocateModule = new AllocateModule();

        // Deploy and approve predeposit vault implementation
        vm.startPrank(factoryOwner);
        factory.approveImplementation(address(new ConcretePredepositVaultImpl(address(factory))));
        vm.stopPrank();

        // Deploy predeposit vault on chain A
        predepositVault = ConcretePredepositVaultImpl(
            factory.create(
                2,
                vaultOwner,
                abi.encode(address(allocateModule), address(asset), vaultManager, "Concrete Predeposit Vault A", "CPVA")
            )
        );

        // Deploy OApp for predeposit vault
        predepositVaultOApp = PredepostVaultOApp(
            address(
                new ERC1967Proxy(
                    address(new PredepostVaultOApp(address(endpoints[aEid]))),
                    abi.encodeCall(PredepostVaultOApp.initialize, (address(predepositVault), vaultOwner))
                )
            )
        );

        // Deploy destination vault on chain B
        destinationVault = ConcreteStandardVaultImpl(
            factory.create(
                1,
                vaultOwner,
                abi.encode(address(allocateModule), address(asset), vaultManager, "Concrete Standard Vault B", "CSVB")
            )
        );

        // Deploy REAL ShareDistributor on chain B using proxy pattern
        ShareDistributor distributorImpl = new ShareDistributor(address(endpoints[bEid]));
        bytes memory initData = abi.encodeCall(ShareDistributor.initialize, (address(destinationVault), vaultManager));
        ERC1967Proxy distributorProxy = new ERC1967Proxy(address(distributorImpl), initData);
        distributor = ShareDistributor(address(distributorProxy));

        // Deploy strategy
        strategy = new ERC4626StrategyMock(address(asset));
    }

    function _setupLabels() private {
        vm.label(address(predepositVault), "predepositVault");
        vm.label(address(predepositVaultOApp), "predepositVaultOApp");
        vm.label(address(destinationVault), "destinationVault");
        vm.label(address(distributor), "distributor");
        vm.label(address(asset), "asset");
        vm.label(address(endpoints[aEid]), "endpointA");
        vm.label(address(endpoints[bEid]), "endpointB");
    }

    function _configureConnections() private {
        // Set OApp in predeposit vault and enable self claims
        vm.startPrank(vaultManager);
        predepositVault.setOApp(address(predepositVaultOApp));
        predepositVault.setSelfClaimsEnabled(true); // Enable self claims for testing
        vm.stopPrank();

        // Configure OApp peer and destination
        vm.startPrank(vaultOwner);
        predepositVaultOApp.setPeer(bEid, addressToBytes32(address(distributor)));
        predepositVaultOApp.setDstEid(bEid);
        vm.stopPrank();

        // Configure distributor peer
        vm.prank(vaultManager);
        distributor.setPeer(aEid, addressToBytes32(address(predepositVaultOApp)));
    }

    function _setupRoles() private {
        vm.startPrank(vaultManager);
        predepositVault.grantRole(RolesLib.STRATEGY_MANAGER, strategyOperator);
        predepositVault.grantRole(RolesLib.ALLOCATOR, allocator);
        vm.stopPrank();
    }

    function _setupUsers() private {
        // Fund users with assets
        asset.mint(user1, 10000e18);
        asset.mint(user2, 10000e18);
        asset.mint(user3, 10000e18);

        // Fund users with ETH for LayerZero fees
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
        vm.deal(vaultManager, 10 ether);

        // Approve vault
        vm.prank(user1);
        asset.approve(address(predepositVault), 10000e18);

        vm.prank(user2);
        asset.approve(address(predepositVault), 10000e18);

        vm.prank(user3);
        asset.approve(address(predepositVault), 10000e18);

        // Add strategy to vault
        vm.prank(strategyOperator);
        predepositVault.addStrategy(address(strategy));

        // Set deallocation order
        address[] memory order = new address[](1);
        order[0] = address(strategy);
        vm.prank(allocator);
        predepositVault.setDeallocationOrder(order);

        // Users deposit into vault A
        vm.prank(user1);
        predepositVault.deposit(5000e18, user1);

        vm.prank(user2);
        predepositVault.deposit(3000e18, user2);

        vm.prank(user3);
        predepositVault.deposit(2000e18, user3);

        // Allocate all assets to strategy
        _allocateAllToStrategy();

        // Lock deposits and withdrawals before allowing claims
        vm.startPrank(vaultManager);
        predepositVault.setDepositLimits(0, 0);
        predepositVault.setWithdrawLimits(0, 0);
        vm.stopPrank();
    }

    function _fundDistributor() private {
        // Fund the distributor with vault shares (equivalent to total supply)
        uint256 distributorFunding = predepositVault.totalSupply();
        asset.mint(address(distributor), distributorFunding);
        vm.startPrank(address(distributor));
        asset.approve(address(destinationVault), distributorFunding);
        destinationVault.deposit(distributorFunding, address(distributor));
        vm.stopPrank();
    }

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

    /*//////////////////////////////////////////////////////////////
                        SINGLE CLAIM E2E TESTS
    //////////////////////////////////////////////////////////////*/

    function test_E2E_singleClaim_fullFlow() public {
        uint256 user1SharesBefore = predepositVault.balanceOf(user1);
        assertGt(user1SharesBefore, 0, "User should have shares");

        // Check initial state on destination chain
        uint256 user1DestSharesBefore = destinationVault.balanceOf(user1);
        uint256 distributorSharesBefore = distributor.getAvailableShares();
        assertEq(user1DestSharesBefore, 0, "User should have no destination shares initially");
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
        uint256 user1DestSharesAfter = destinationVault.balanceOf(user1);
        uint256 distributorSharesAfter = distributor.getAvailableShares();

        assertEq(user1DestSharesAfter, user1SharesBefore, "User should receive destination shares");
        assertEq(
            distributorSharesAfter, distributorSharesBefore - user1SharesBefore, "Distributor shares should decrease"
        );
    }

    function test_E2E_multipleUsersClaim() public {
        uint256 user1Shares = predepositVault.balanceOf(user1);
        uint256 user2Shares = predepositVault.balanceOf(user2);
        uint256 user3Shares = predepositVault.balanceOf(user3);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());

        // User1 claims
        MessagingFee memory fee1 = oapp.quoteClaimOnTargetChain(user1, options, false);
        vm.prank(user1);
        predepositVault.claimOnTargetChain{value: fee1.nativeFee}(options);
        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // User2 claims
        MessagingFee memory fee2 = oapp.quoteClaimOnTargetChain(user2, options, false);
        vm.prank(user2);
        predepositVault.claimOnTargetChain{value: fee2.nativeFee}(options);
        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // User3 claims
        MessagingFee memory fee3 = oapp.quoteClaimOnTargetChain(user3, options, false);
        vm.prank(user3);
        predepositVault.claimOnTargetChain{value: fee3.nativeFee}(options);
        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // All users should have their shares burned on chain A
        assertEq(predepositVault.balanceOf(user1), 0);
        assertEq(predepositVault.balanceOf(user2), 0);
        assertEq(predepositVault.balanceOf(user3), 0);

        // All users should have their locked shares tracked
        assertEq(predepositVault.getLockedShares(user1), user1Shares);
        assertEq(predepositVault.getLockedShares(user2), user2Shares);
        assertEq(predepositVault.getLockedShares(user3), user3Shares);

        // All users should have received destination shares
        assertEq(destinationVault.balanceOf(user1), user1Shares);
        assertEq(destinationVault.balanceOf(user2), user2Shares);
        assertEq(destinationVault.balanceOf(user3), user3Shares);
    }

    /*//////////////////////////////////////////////////////////////
                        BATCH CLAIM E2E TESTS
    //////////////////////////////////////////////////////////////*/

    function test_E2E_batchClaim_fullFlow() public {
        uint256 user1SharesBefore = predepositVault.balanceOf(user1);
        uint256 user2SharesBefore = predepositVault.balanceOf(user2);
        uint256 user3SharesBefore = predepositVault.balanceOf(user3);

        // Check initial state on destination chain
        uint256 distributorSharesBefore = distributor.getAvailableShares();
        assertGt(distributorSharesBefore, 0, "Distributor should have shares");

        // Build options for batch operation
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300000, 0);

        // Prepare batch data
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
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
        assertEq(predepositVault.balanceOf(user3), 0, "User3 shares should be burned");

        // Check locked shares tracking
        assertEq(predepositVault.getLockedShares(user1), user1SharesBefore);
        assertEq(predepositVault.getLockedShares(user2), user2SharesBefore);
        assertEq(predepositVault.getLockedShares(user3), user3SharesBefore);

        // Check shares distributed on chain B
        assertEq(destinationVault.balanceOf(user1), user1SharesBefore, "User1 should receive shares on chain B");
        assertEq(destinationVault.balanceOf(user2), user2SharesBefore, "User2 should receive shares on chain B");
        assertEq(destinationVault.balanceOf(user3), user3SharesBefore, "User3 should receive shares on chain B");

        // Check claimed shares tracking on distributor
        assertEq(distributor.claimedShares(user1), user1SharesBefore);
        assertEq(distributor.claimedShares(user2), user2SharesBefore);
        assertEq(distributor.claimedShares(user3), user3SharesBefore);
    }

    function test_E2E_batchClaim_withDuplicates() public {
        // Create array with duplicate users
        address[] memory users = new address[](4);
        users[0] = user1;
        users[1] = user2;
        users[2] = user1; // Duplicate
        users[3] = user2; // Duplicate

        uint256 user1SharesBefore = predepositVault.balanceOf(user1);
        uint256 user2SharesBefore = predepositVault.balanceOf(user2);

        bytes memory addressesData = abi.encode(users);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300000, 0);

        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteBatchClaimOnTargetChain(addressesData, options, false);

        // Batch claim should succeed - duplicates are skipped
        vm.prank(vaultManager);
        predepositVault.batchClaimOnTargetChain{value: fee.nativeFee}(addressesData, options);

        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // Users should have their shares burned (only once)
        assertEq(predepositVault.balanceOf(user1), 0);
        assertEq(predepositVault.balanceOf(user2), 0);

        // Users should receive shares only once on destination
        assertEq(destinationVault.balanceOf(user1), user1SharesBefore);
        assertEq(destinationVault.balanceOf(user2), user2SharesBefore);
    }

    /*//////////////////////////////////////////////////////////////
                    EXCHANGE RATE INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_E2E_exchangeRate_remainsConstant() public {
        // Get initial exchange rate
        uint256 decimals = predepositVault.decimals();
        uint256 oneShare = 10 ** decimals;
        uint256 initialExchangeRate = predepositVault.convertToAssets(oneShare);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());

        // User1 claims
        MessagingFee memory fee = oapp.quoteClaimOnTargetChain(user1, options, false);
        vm.prank(user1);
        predepositVault.claimOnTargetChain{value: fee.nativeFee}(options);
        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // Check exchange rate after first claim
        if (predepositVault.totalSupply() > 0) {
            uint256 exchangeRateAfter = predepositVault.convertToAssets(oneShare);
            uint256 diff = exchangeRateAfter > initialExchangeRate
                ? exchangeRateAfter - initialExchangeRate
                : initialExchangeRate - exchangeRateAfter;
            uint256 maxDiff = initialExchangeRate / 10000; // 0.01%
            assertLe(diff, maxDiff, "Exchange rate should remain nearly constant");
        }

        // User2 claims
        vm.prank(user2);
        predepositVault.claimOnTargetChain{value: fee.nativeFee}(options);
        verifyPackets(bEid, addressToBytes32(address(distributor)));

        // Check exchange rate after second claim
        if (predepositVault.totalSupply() > 0) {
            uint256 exchangeRateAfter = predepositVault.convertToAssets(oneShare);
            uint256 diff = exchangeRateAfter > initialExchangeRate
                ? exchangeRateAfter - initialExchangeRate
                : initialExchangeRate - exchangeRateAfter;
            uint256 maxDiff = initialExchangeRate / 10000; // 0.01%
            assertLe(diff, maxDiff, "Exchange rate should remain nearly constant");
        }
    }

    /*//////////////////////////////////////////////////////////////
                    EMERGENCY WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_E2E_emergencyWithdraw() public {
        uint256 withdrawAmount = 1000e18;
        uint256 managerBalanceBefore = destinationVault.balanceOf(vaultManager);
        uint256 distributorBalanceBefore = distributor.getAvailableShares();

        vm.prank(vaultManager);
        distributor.emergencyWithdraw(withdrawAmount);

        assertEq(
            destinationVault.balanceOf(vaultManager),
            managerBalanceBefore + withdrawAmount,
            "Manager should receive shares"
        );
        assertEq(
            distributor.getAvailableShares(),
            distributorBalanceBefore - withdrawAmount,
            "Distributor balance should decrease"
        );
    }

    /*//////////////////////////////////////////////////////////////
                    VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_E2E_revertsWhenSelfClaimsDisabled() public {
        // Disable self claims
        vm.prank(vaultManager);
        predepositVault.setSelfClaimsEnabled(false);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        vm.expectRevert(IConcretePredepositVaultImpl.SelfClaimsDisabled.selector);
        vm.prank(user1);
        predepositVault.claimOnTargetChain{value: 0.01 ether}(options);
    }

    function test_E2E_revertsWhenDepositsNotLocked() public {
        // Unlock deposits
        vm.prank(vaultManager);
        predepositVault.setDepositLimits(0, type(uint256).max);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        IPredepostVaultOApp oapp = IPredepostVaultOApp(predepositVault.getOApp());
        MessagingFee memory fee = oapp.quoteClaimOnTargetChain(user1, options, false);

        vm.expectRevert(IConcretePredepositVaultImpl.DepositsNotLocked.selector);
        vm.prank(user1);
        predepositVault.claimOnTargetChain{value: fee.nativeFee}(options);
    }

    function test_E2E_revertsWithNoShares() public {
        address noSharesUser = makeAddr("noSharesUser");
        vm.deal(noSharesUser, 1 ether);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        vm.expectRevert(IConcretePredepositVaultImpl.NoSharesToClaim.selector);
        vm.prank(noSharesUser);
        predepositVault.claimOnTargetChain{value: 0.01 ether}(options);
    }
}

