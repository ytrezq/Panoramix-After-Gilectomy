// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IRewardsController, AaveV3ATokenWrapper, NotCollateralVault, ZeroIncentivesControllerIsForbidden, CallerNotAdmin, CallerNotOwnerOrPauseGuardian} from "src/AaveV3ATokenWrapper.sol";
import {IPool} from "aave-v3/interfaces/IPool.sol";
import {IERC20}  from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}  from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAToken} from "aave-v3/interfaces/IAToken.sol";
import {AToken} from "aave-v3/protocol/tokenization/AToken.sol";
import {TestnetProcedures, TestnetERC20} from 'aave-v3-origin/tests/utils/TestnetProcedures.sol';
import {PullRewardsTransferStrategy, ITransferStrategyBase} from 'aave-v3-origin/src/contracts/rewards/transfer-strategies/PullRewardsTransferStrategy.sol';
import {RewardsDataTypes} from 'aave-v3-origin/src/contracts/rewards/libraries/RewardsDataTypes.sol';
import {AggregatorInterface} from 'aave-v3-origin/src/contracts/dependencies/chainlink/AggregatorInterface.sol';

contract MockCollateralVaultFactory {
    address public immutable EVC;
    mapping(address => bool) public isCollateralVault;

    constructor(address _evc) {
        EVC = _evc;
    }

    function setIsCollateralVault(address asset, bool status) external {
        isCollateralVault[asset] = status;
    }
}

contract AaveV3ATokenWrapperTest is Test, TestnetProcedures {
    AaveV3ATokenWrapper tokenWrapper;

    // Chain-specific addresses
    address WSTETH;
    address aavePoolAddress;
    address aToken;

    MockCollateralVaultFactory collateralVaultFactory;
    IPool aavePool;
    address owner;
    uint DEPOSIT_AMOUNT_INIT = 100 ether;
    uint DEPOSIT_AMOUNT = 20 ether;

    // Reward testing variables
    uint256 internal userPrivateKey;
    address internal user;
    address internal rewardToken;
    address internal emissionAdmin;
    PullRewardsTransferStrategy strategy;

    struct TestEnv {
        uint256 depositAmount;
        uint32 emissionEnd;
        uint88 emissionPerSecond;
        uint32 emissionDuration;
    }

    error UnknownProfile();

    function setUp() public {
        // Set chain-specific addresses
        if (block.chainid == 1) {
            // Ethereum Mainnet
            WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
            aavePoolAddress = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
        } else if (block.chainid == 8453) {
            // Base
            WSTETH = 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452;
            aavePoolAddress = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
        } else {
            revert UnknownProfile();
        }

        aavePool = IPool(aavePoolAddress);

        aToken = aavePool.getReserveData(WSTETH).aTokenAddress;
        require(IAToken(aToken).UNDERLYING_ASSET_ADDRESS() == WSTETH, "underlying asset not correct");

        // Initialize Aave testnet environment
        initTestEnvironment(false);

        owner = makeAddr('owner');
        alice = makeAddr('alice');
        bob = makeAddr('bob');

        // Setup reward testing variables
        emissionAdmin = vm.addr(1024);
        userPrivateKey = 0xA11CE;
        user = address(vm.addr(userPrivateKey));

        address evc = 0x0C9a3dd6b8F28529d72d7f9cE918D493519EE383;
        collateralVaultFactory = new MockCollateralVaultFactory(evc);

        // Deploy implementation
        address implementation = address(new AaveV3ATokenWrapper(
            evc,
            address(collateralVaultFactory),
            aavePool,
            contracts.rewardsControllerProxy // Use the one from TestnetProcedures
        ));

        // Encode initialization data
        bytes memory initData = abi.encodeCall(
            AaveV3ATokenWrapper.initialize,
            (aToken, address(this), "A-Stat-WSTETH", "ASWSTETH")
        );

        // Deploy proxy
        address proxy = address(new ERC1967Proxy(implementation, initData));
        tokenWrapper = AaveV3ATokenWrapper(proxy);

        // Setup reward token and strategy
        rewardToken = address(new TestnetERC20('LM Reward ERC20', 'RWD', 18, poolAdmin));
        strategy = new PullRewardsTransferStrategy(
            report.rewardsControllerProxy,
            emissionAdmin,
            emissionAdmin
        );

        vm.prank(poolAdmin);
        contracts.emissionManager.setEmissionAdmin(rewardToken, emissionAdmin);

        deal(WSTETH, alice, DEPOSIT_AMOUNT);
        deal(WSTETH, bob, DEPOSIT_AMOUNT_INIT);
        deal(WSTETH, user, DEPOSIT_AMOUNT);
    }

    function depositToAave(address userAddr, address asset, uint amount) internal {
        vm.startPrank(userAddr);

        IERC20(asset).approve(address(aavePool), amount);

        aavePool.supply(asset, amount, userAddr, 0);

        vm.stopPrank();
    }


    function aave_createDeposit() public {
        vm.startPrank(bob);

        IERC20(WSTETH).approve(address(tokenWrapper), DEPOSIT_AMOUNT_INIT);
        uint expectedShares = tokenWrapper.previewDeposit(DEPOSIT_AMOUNT_INIT);

        tokenWrapper.deposit(DEPOSIT_AMOUNT_INIT, bob);

        vm.stopPrank();
        assertEq(tokenWrapper.balanceOf(bob), expectedShares, "Incorrect shares received");
    }

    function a_deposit(uint amount) public {
        vm.startPrank(alice);
        uint expectedShares = tokenWrapper.previewDeposit(amount);
        IERC20(WSTETH).approve(address(tokenWrapper), amount);

        tokenWrapper.deposit(amount, alice);

        vm.stopPrank();
        assertEq(tokenWrapper.balanceOf(alice), expectedShares, "Incorrect shares received");
    }


    function a_withdraw(uint shares) internal {
        uint balanceBefore = IERC20(WSTETH).balanceOf(alice);
        vm.startPrank(alice);

        uint amountExpected = tokenWrapper.previewRedeem(shares);
        tokenWrapper.redeem(shares, alice, alice);

        vm.stopPrank();
        assertEq(IERC20(WSTETH).balanceOf(alice) - balanceBefore, amountExpected);
    }

    function test_deposit() public {
        aave_createDeposit();
        a_deposit(DEPOSIT_AMOUNT);
    }

    function test_withdraw() public {
        aave_createDeposit();
        a_deposit(DEPOSIT_AMOUNT);

        a_withdraw(tokenWrapper.balanceOf(alice));
    }

    function test_fuzz_deposit(uint256 amount) public {
        vm.assume(amount > 100 && amount <= DEPOSIT_AMOUNT);
        aave_createDeposit();
        a_deposit(amount);
    }

    function test_fuzz_withdraw(uint amount) public {
        aave_createDeposit();
        a_deposit(DEPOSIT_AMOUNT);
        uint sharesMax = tokenWrapper.balanceOf(alice);
        vm.assume(amount <= sharesMax && amount > 100);
        a_withdraw(sharesMax);
    }

    function test_rebalanceATokens_CV() public {
        aave_createDeposit();
        vm.startPrank(alice);
        vm.expectRevert(NotCollateralVault.selector);

        tokenWrapper.rebalanceATokens_CV(0);

        uint totalAssetsBefore = tokenWrapper.totalAssets();
        collateralVaultFactory.setIsCollateralVault(alice, true);
        uint amountExpected = tokenWrapper.previewRedeem(1e18);

        tokenWrapper.rebalanceATokens_CV(1e18);

        assertEq(IERC20(aToken).balanceOf(alice), amountExpected, "Not received correct amount");
        assertEq(tokenWrapper.previewRedeem(1e18), amountExpected, "Preview redeem should give same value");
        assertEq(tokenWrapper.totalAssets(), totalAssetsBefore, "Total assets not same");
        vm.stopPrank();
    }


    function test_burnShares_CV() public {
        aave_createDeposit();
        a_deposit(10e18);
        vm.startPrank(alice);
        vm.expectRevert(NotCollateralVault.selector);

        tokenWrapper.burnShares_CV(0);

        uint totalSupplyBefore = tokenWrapper.totalSupply();
        uint aliceSharesBefore = tokenWrapper.balanceOf(alice);
        collateralVaultFactory.setIsCollateralVault(alice, true);

        // Now burnShares_CV takes shares directly, not assets
        uint sharesToBurn = 1e18;
        tokenWrapper.burnShares_CV(sharesToBurn);

        assertEq(tokenWrapper.totalSupply(), totalSupplyBefore - sharesToBurn, "Total supply after is not expected");
        assertEq(tokenWrapper.balanceOf(alice), aliceSharesBefore - sharesToBurn, "Shares burned should match requested amount");
        vm.stopPrank();
    }

    function test_donationAttack() public {

        uint firstDeposit = 2;

        address attacker = makeAddr("attacker");

        deal(WSTETH, attacker, 100e18);

        vm.startPrank(attacker);

        IERC20(WSTETH).approve(address(tokenWrapper), 100e18);
        tokenWrapper.deposit(firstDeposit, attacker);
        vm.stopPrank();

        depositToAave(attacker, WSTETH, 10e18);

        uint balance = IERC20(aToken).balanceOf(attacker);
        vm.prank(attacker);
        IERC20(aToken).transfer(address(tokenWrapper), balance);

        a_deposit(1e18);

        assertGe(tokenWrapper.balanceOf(alice), 5e17);

        vm.startPrank(attacker);
        uint assetsReceived = tokenWrapper.redeem(tokenWrapper.balanceOf(attacker), attacker, attacker);
        assertLt(assetsReceived, 10e18);
    }

    // Test pause functionality
    function test_pauseUnpause() public {
        aave_createDeposit();

        address pauseGuardian = makeAddr("pauseGuardian");

        // Only admin can configure the pause guardian.
        vm.prank(alice);
        vm.expectRevert(CallerNotAdmin.selector);
        tokenWrapper.setPauseGuardian(pauseGuardian);

        tokenWrapper.setPauseGuardian(pauseGuardian);
        assertEq(tokenWrapper.pauseGuardian(), pauseGuardian);

        // Guardian can pause.
        vm.prank(pauseGuardian);
        tokenWrapper.pause();
        assertTrue(tokenWrapper.paused());

        // Operations should fail when paused
        vm.startPrank(alice);
        vm.expectRevert();
        tokenWrapper.deposit(1e18, alice);
        vm.stopPrank();

        // Guardian cannot unpause; only admin can.
        vm.prank(pauseGuardian);
        vm.expectRevert(CallerNotAdmin.selector);
        tokenWrapper.unpause();

        tokenWrapper.unpause();
        assertFalse(tokenWrapper.paused());

        // Operations should work again
        a_deposit(DEPOSIT_AMOUNT);
    }

    // Test ERC4626 mint function
    function test_mint() public {
        aave_createDeposit();

        uint sharesToMint = 10e18;
        uint assetsRequired = tokenWrapper.previewMint(sharesToMint);

        deal(WSTETH, alice, assetsRequired);

        vm.startPrank(alice);
        IERC20(WSTETH).approve(address(tokenWrapper), assetsRequired);
        uint assetsUsed = tokenWrapper.mint(sharesToMint, alice);
        vm.stopPrank();

        assertEq(tokenWrapper.balanceOf(alice), sharesToMint);
        assertEq(assetsUsed, assetsRequired);
    }

    // Test ERC4626 withdraw function
    function test_withdrawAssets() public {
        aave_createDeposit();
        a_deposit(DEPOSIT_AMOUNT);

        uint assetsToWithdraw = 5e18;
        uint sharesRequired = tokenWrapper.previewWithdraw(assetsToWithdraw);
        uint balanceBefore = IERC20(WSTETH).balanceOf(alice);

        vm.startPrank(alice);
        uint sharesUsed = tokenWrapper.withdraw(assetsToWithdraw, alice, alice);
        vm.stopPrank();

        assertEq(sharesUsed, sharesRequired);
        assertEq(IERC20(WSTETH).balanceOf(alice) - balanceBefore, assetsToWithdraw);
    }

    // Test max functions
    function test_maxDeposit() public {
        aave_createDeposit();

        // Max deposit should return unlimited amount
        uint256 maxDep = tokenWrapper.maxDeposit(alice);
        assertEq(maxDep, type(uint256).max);

        // When paused, deposits should revert (not necessarily return 0)
        vm.prank(address(this));
        tokenWrapper.pause();

        // Try to deposit when paused - should revert
        vm.startPrank(alice);
        vm.expectRevert();
        tokenWrapper.deposit(1e18, alice);
        vm.stopPrank();
    }

    function test_maxMint() public {
        aave_createDeposit();

        // Max mint should return unlimited amount
        uint256 maxM = tokenWrapper.maxMint(alice);
        assertEq(maxM, type(uint256).max);

        // When paused, minting should revert (not necessarily return 0)
        vm.prank(address(this));
        tokenWrapper.pause();

        // Try to mint when paused - should revert
        vm.startPrank(alice);
        vm.expectRevert();
        tokenWrapper.mint(1e18, alice);
        vm.stopPrank();
    }

    function test_maxWithdraw() public {
        aave_createDeposit();
        a_deposit(DEPOSIT_AMOUNT);

        uint maxAssets = tokenWrapper.maxWithdraw(alice);
        // Should return unlimited withdrawals
        assertEq(maxAssets, type(uint256).max);
    }

    function test_maxRedeem() public {
        aave_createDeposit();
        a_deposit(DEPOSIT_AMOUNT);

        uint maxShares = tokenWrapper.maxRedeem(alice);
        // Should return unlimited redemptions
        assertEq(maxShares, type(uint256).max);
    }

    // Test rebalanceATokens_CV edge cases
    function test_rebalanceATokens_CV_multipleRebalances() public {
        aave_createDeposit();
        collateralVaultFactory.setIsCollateralVault(alice, true);

        vm.startPrank(alice);
        IERC20(aToken).approve(address(tokenWrapper), type(uint256).max);

        // First rebalance - get some aTokens
        uint expectedATokenBalance_CV = tokenWrapper.previewRedeem(10e18);
        uint aliceShares = tokenWrapper.balanceOf(alice);
        tokenWrapper.rebalanceATokens_CV(10e18);
        uint firstBalance = IERC20(aToken).balanceOf(alice);
        assertEq(firstBalance, expectedATokenBalance_CV, "Should receive exact expected aTokens");
        assertEq(tokenWrapper.balanceOf(alice), aliceShares, "Should receive exact expected aTokens");

        // Second rebalance - increase position
        tokenWrapper.rebalanceATokens_CV(20e18);
        uint secondBalance = IERC20(aToken).balanceOf(alice);
        assertGt(secondBalance, firstBalance);

        // Third rebalance - decrease position
        tokenWrapper.rebalanceATokens_CV(5e18);
        uint thirdBalance = IERC20(aToken).balanceOf(alice);
        assertLt(thirdBalance, secondBalance);

        vm.stopPrank();
    }

    function test_rebalanceATokens_CV_withExcessATokens() public {
        aave_createDeposit();
        collateralVaultFactory.setIsCollateralVault(alice, true);

        // Give alice some aTokens directly
        depositToAave(alice, WSTETH, 10e18);
        uint initialATokenBalance = IERC20(aToken).balanceOf(alice);

        // Rebalance to a smaller amount
        vm.startPrank(alice);
        IERC20(aToken).approve(address(tokenWrapper), type(uint256).max);
        tokenWrapper.rebalanceATokens_CV(1e18);
        vm.stopPrank();

        // Alice should have less aTokens now
        uint finalATokenBalance = IERC20(aToken).balanceOf(alice);
        assertLt(finalATokenBalance, initialATokenBalance);

        // Allow for small rounding differences (1 wei)
        uint expectedBalance = tokenWrapper.previewRedeem(1e18);
        assertLe(finalATokenBalance, expectedBalance + 1);
        assertGe(finalATokenBalance, expectedBalance - 1);
    }

    // Test burnShares_CV with various amounts
    function test_burnShares_CV_partialBurn() public {
        aave_createDeposit();
        a_deposit(20e18);

        collateralVaultFactory.setIsCollateralVault(alice, true);

        uint initialBalance = tokenWrapper.balanceOf(alice);
        // Now burnShares_CV takes shares directly
        uint sharesToBurn = 5e18;

        vm.prank(alice);
        tokenWrapper.burnShares_CV(sharesToBurn);

        assertEq(tokenWrapper.balanceOf(alice), initialBalance - sharesToBurn);
    }

    function test_burnShares_CV_fullBurn() public {
        aave_createDeposit();
        a_deposit(10e18);

        collateralVaultFactory.setIsCollateralVault(alice, true);

        // Get all shares to burn
        uint allShares = tokenWrapper.balanceOf(alice);

        vm.prank(alice);
        tokenWrapper.burnShares_CV(allShares);

        // Alice should have 0 shares
        assertEq(tokenWrapper.balanceOf(alice), 0);
    }

    // Test interactions between CV functions
    function test_CV_functions_interaction() public {
        aave_createDeposit();
        a_deposit(20e18);

        collateralVaultFactory.setIsCollateralVault(alice, true);

        vm.startPrank(alice);

        // Approve the wrapper to transfer aTokens
        IERC20(aToken).approve(address(tokenWrapper), type(uint256).max);

        // First rebalance to get aTokens
        tokenWrapper.rebalanceATokens_CV(10e18);
        uint aTokenBalance = IERC20(aToken).balanceOf(alice);

        // Burn some shares
        tokenWrapper.burnShares_CV(5e18);

        // Rebalance should still work correctly after burn
        tokenWrapper.rebalanceATokens_CV(5e18);
        uint newATokenBalance = IERC20(aToken).balanceOf(alice);

        // Should have less aTokens after burning shares and rebalancing to lower amount
        assertLt(newATokenBalance, aTokenBalance);

        vm.stopPrank();
    }

    // Test that non-collateral vaults cannot call CV functions
    function test_CV_functions_accessControl() public {
        aave_createDeposit();
        a_deposit(10e18);

        // Bob is not a collateral vault
        vm.startPrank(bob);

        vm.expectRevert(NotCollateralVault.selector);
        tokenWrapper.rebalanceATokens_CV(1e18);

        vm.expectRevert(NotCollateralVault.selector);
        tokenWrapper.burnShares_CV(1e18);

        vm.stopPrank();

        // After setting bob as collateral vault, functions should work
        collateralVaultFactory.setIsCollateralVault(bob, true);

        vm.prank(bob);
        tokenWrapper.rebalanceATokens_CV(0); // Should not revert
    }

    // Test convertToShares and convertToAssets
    function test_conversionFunctions() public {
        aave_createDeposit();

        // Test round-trip conversion
        uint assets = 10e18;
        uint shares = tokenWrapper.convertToShares(assets);
        uint assetsBack = tokenWrapper.convertToAssets(shares);

        // Due to rounding, assetsBack might be slightly less than assets
        assertLe(assetsBack, assets);
        assertGe(assetsBack, assets - 10); // Allow small rounding difference

        // Test exact rate calculation
        uint256 rate = aavePool.getReserveNormalizedIncome(tokenWrapper.asset());
        uint256 RAY = 1e27;

        uint256 testAmount = 1e18;
        uint256 expectedShares = (testAmount * RAY) / rate;
        uint256 expectedAssets = (testAmount * rate) / RAY;

        assertEq(tokenWrapper.convertToShares(testAmount), expectedShares, "convertToShares exact calculation mismatch");
        assertEq(tokenWrapper.convertToAssets(testAmount), expectedAssets, "convertToAssets exact calculation mismatch");

        // Test conversion logic bounds
        uint256 actualShares = tokenWrapper.convertToShares(testAmount);
        uint256 actualAssets = tokenWrapper.convertToAssets(testAmount);

        // convertToShares(assets) should be > 0 and < assets (due to accumulated interest rate > RAY)
        assertGt(actualShares, 0, "convertToShares should be > 0");
        assertLt(actualShares, testAmount, "convertToShares should be < assets due to rate > RAY");

        // convertToAssets(shares) should be > shares (due to accumulated interest)
        assertGt(actualAssets, testAmount, "convertToAssets should be > shares due to rate > RAY");
    }

    // Test totalAssets tracking
    function test_totalAssets() public {
        uint initialTotal = tokenWrapper.totalAssets();

        aave_createDeposit();
        uint afterFirstDeposit = tokenWrapper.totalAssets();
        assertGt(afterFirstDeposit, initialTotal);

        a_deposit(DEPOSIT_AMOUNT);
        uint afterSecondDeposit = tokenWrapper.totalAssets();
        assertGt(afterSecondDeposit, afterFirstDeposit);

        // Total assets should be at least close to deposits (allowing for small rounding)
        assertGe(afterSecondDeposit, DEPOSIT_AMOUNT_INIT + DEPOSIT_AMOUNT - 1e15);
    }

    // Test owner functions
    function test_ownershipTransfer() public {
        address newOwner = makeAddr("newOwner");
        address newAdmin = makeAddr("newAdmin");

        // Transfer ownership
        tokenWrapper.transferOwnership(newOwner);
        assertEq(tokenWrapper.owner(), newOwner);
        assertEq(tokenWrapper.admin(), address(this));

        // Ownership transfer does not change operational admin.
        tokenWrapper.pause();
        assertTrue(tokenWrapper.paused());
        tokenWrapper.unpause();

        vm.prank(newOwner);
        tokenWrapper.setAdmin(newAdmin);
        assertEq(tokenWrapper.admin(), newAdmin);

        vm.expectRevert(CallerNotOwnerOrPauseGuardian.selector);
        tokenWrapper.pause();

        vm.prank(newAdmin);
        tokenWrapper.pause();
        assertTrue(tokenWrapper.paused());
    }

    // Fuzzing test for rebalanceATokens with scaledBalance verification
    function test_fuzz_rebalanceATokens_scaledBalance(uint256 depositAmount, uint256 iterations) public {
        // Bound the input values
        depositAmount = bound(depositAmount, 1e18, 100e18); // Between 1 and 100 WSTETH
        iterations = bound(iterations, 1, 5); // Do 1-5 iterations of deposits/rebalances

        // Setup: Create initial deposit to avoid division by zero
        aave_createDeposit();

        // Make alice a collateral vault
        address vault = alice;
        collateralVaultFactory.setIsCollateralVault(vault, true);

        // Give vault some WSTETH and deposit to wrapper
        deal(WSTETH, vault, depositAmount * 2); // Give extra for later deposits
        vm.startPrank(vault);
        IERC20(WSTETH).approve(address(tokenWrapper), type(uint256).max);
        tokenWrapper.deposit(depositAmount, vault);

        // Get initial wrapper balance
        uint256 wrapperBalance = tokenWrapper.balanceOf(vault);

        // Approve wrapper to transfer aTokens
        IAToken aTokenContract = IAToken(aToken);
        IERC20(aToken).approve(address(tokenWrapper), type(uint256).max);

        // Call rebalanceATokens_CV with the vault's wrapper balance
        tokenWrapper.rebalanceATokens_CV(wrapperBalance);

        // Verify that scaledBalanceOf(vault) equals wrapper.balanceOf(vault)
        uint256 scaledBalance = aTokenContract.scaledBalanceOf(vault);
        assertEq(scaledBalance, wrapperBalance, "Scaled balance should equal wrapper balance after rebalance");

        vm.stopPrank();

        // Additional verification: Do multiple rounds with different amounts
        for (uint256 i = 0; i < iterations; i++) {
            vm.startPrank(vault);

            // Get current balances
            uint256 currentWrapperBalance = tokenWrapper.balanceOf(vault);
            uint256 currentWSTETHBalance = IERC20(WSTETH).balanceOf(vault);

            if (i % 2 == 0 && currentWrapperBalance > 1e17) {
                // Withdraw some (but not too much)
                uint256 withdrawAmount = bound(uint256(keccak256(abi.encode("withdraw", i))), 1e17, currentWrapperBalance / 2);
                tokenWrapper.redeem(withdrawAmount, vault, vault);
            } else if (currentWSTETHBalance >= 1e17) {
                // Deposit more
                uint256 depositAmt = bound(uint256(keccak256(abi.encode("deposit", i))), 1e17, currentWSTETHBalance);
                tokenWrapper.deposit(depositAmt, vault);
            }

            // Get updated wrapper balance
            wrapperBalance = tokenWrapper.balanceOf(vault);

            // Rebalance again
            if (wrapperBalance > 0) {
                tokenWrapper.rebalanceATokens_CV(wrapperBalance);

                // Verify equality again
                scaledBalance = aTokenContract.scaledBalanceOf(vault);
                assertEq(scaledBalance, wrapperBalance,
                    string.concat("Iteration ", vm.toString(i), ": Scaled balance should equal wrapper balance"));
            }

            vm.stopPrank();
        }
    }

    // Additional test: Verify rebalanceATokens with partial shares
    function test_fuzz_rebalanceATokens_partialShares(uint256 depositAmount, uint256 sharesFraction) public {
        // Bound inputs
        depositAmount = bound(depositAmount, 10e18, 100e18);
        sharesFraction = bound(sharesFraction, 1, 100); // 1-100% of balance

        aave_createDeposit();

        address vault = alice;
        collateralVaultFactory.setIsCollateralVault(vault, true);

        // Deposit and get shares
        deal(WSTETH, vault, depositAmount);
        vm.startPrank(vault);
        IERC20(WSTETH).approve(address(tokenWrapper), depositAmount);
        tokenWrapper.deposit(depositAmount, vault);

        uint256 totalShares = tokenWrapper.balanceOf(vault);
        uint256 partialShares = (totalShares * sharesFraction) / 100;

        // Approve and rebalance with partial shares
        IAToken aTokenContract = IAToken(aToken);
        IERC20(aToken).approve(address(tokenWrapper), type(uint256).max);

        tokenWrapper.rebalanceATokens_CV(partialShares);

        // Verify scaled balance equals the partial shares
        uint256 scaledBalance = aTokenContract.scaledBalanceOf(vault);
        assertEq(scaledBalance, partialShares, "Scaled balance should equal requested partial shares");

        // Rebalance to full amount
        tokenWrapper.rebalanceATokens_CV(totalShares);
        scaledBalance = aTokenContract.scaledBalanceOf(vault);
        assertEq(scaledBalance, totalShares, "Scaled balance should equal total shares after full rebalance");

        vm.stopPrank();
    }

    // Test that rebalanceATokens_CV correctly sets scaledBalance even with airdrops
    function test_fuzz_rebalanceATokens_withAirdrops(uint256 depositAmount, uint256 airdropAmount, uint256 rebalanceAmount) public {
        // Bound inputs
        depositAmount = bound(depositAmount, 10e18, 100e18);
        airdropAmount = bound(airdropAmount, 1e17, 10e18);

        aave_createDeposit();

        // Setup vault
        address vault = alice;
        collateralVaultFactory.setIsCollateralVault(vault, true);

        // Initial deposit
        deal(WSTETH, vault, depositAmount);
        vm.startPrank(vault);
        IERC20(WSTETH).approve(address(tokenWrapper), depositAmount);
        tokenWrapper.deposit(depositAmount, vault);

        // Setup aToken approvals
        IAToken aTokenContract = IAToken(aToken);
        IERC20(aToken).approve(address(tokenWrapper), type(uint256).max);
        vm.stopPrank();

        // Airdrop wrapper shares from bob
        address airdropper = bob;
        deal(WSTETH, airdropper, airdropAmount * 2);
        vm.startPrank(airdropper);
        IERC20(WSTETH).approve(address(tokenWrapper), airdropAmount * 2);
        tokenWrapper.deposit(airdropAmount, airdropper);
        uint256 airdropShares = tokenWrapper.balanceOf(airdropper);
        tokenWrapper.transfer(vault, airdropShares);
        vm.stopPrank();

        // Now vault has more wrapper shares than expected
        uint256 vaultTotalShares = tokenWrapper.balanceOf(vault);

        // Bound rebalance amount to be <= vault's total shares
        rebalanceAmount = bound(rebalanceAmount, 1e16, vaultTotalShares);

        // Vault rebalances to arbitrary amount (not necessarily full balance)
        vm.prank(vault);
        tokenWrapper.rebalanceATokens_CV(rebalanceAmount);

        // Verify scaledBalance equals the rebalance amount (NOT the total wrapper balance)
        uint256 scaledBalance = aTokenContract.scaledBalanceOf(vault);
        assertEq(scaledBalance, rebalanceAmount,
            "Scaled balance should equal the rebalance amount, not total wrapper balance");

        // Verify this holds for different rebalance amounts
        uint256 newRebalanceAmount = bound(uint256(keccak256(abi.encode(rebalanceAmount))), 1e16, vaultTotalShares);
        vm.prank(vault);
        tokenWrapper.rebalanceATokens_CV(newRebalanceAmount);

        scaledBalance = aTokenContract.scaledBalanceOf(vault);
        assertEq(scaledBalance, newRebalanceAmount,
            "Scaled balance should equal new rebalance amount after second rebalance");
    }

    // Test with aToken airdrops
    function test_rebalanceATokens_withATokenAirdrops() public {
        uint256 depositAmount = 50e18;

        aave_createDeposit();

        // Setup vault
        address vault = alice;
        collateralVaultFactory.setIsCollateralVault(vault, true);

        // Initial deposit
        deal(WSTETH, vault, depositAmount);
        vm.startPrank(vault);
        IERC20(WSTETH).approve(address(tokenWrapper), depositAmount);
        tokenWrapper.deposit(depositAmount, vault);

        IAToken aTokenContract = IAToken(aToken);
        IERC20(aToken).approve(address(tokenWrapper), type(uint256).max);

        uint256 initialShares = tokenWrapper.balanceOf(vault);
        vm.stopPrank();

        // Bob airdrops aTokens directly to vault
        address airdropper = bob;
        deal(WSTETH, airdropper, 20e18);
        vm.startPrank(airdropper);
        IERC20(WSTETH).approve(address(tokenWrapper), 20e18);
        tokenWrapper.deposit(20e18, airdropper);
        tokenWrapper.redeem(tokenWrapper.balanceOf(airdropper), airdropper, airdropper);

        // Now bob has aTokens, airdrop them to vault
        uint256 airdropATokenAmount = IERC20(aToken).balanceOf(airdropper);
        IERC20(aToken).transfer(vault, airdropATokenAmount);
        vm.stopPrank();

        // Vault still has same wrapper shares as before
        assertEq(tokenWrapper.balanceOf(vault), initialShares, "Wrapper shares should not change from aToken airdrop");

        // Rebalance to half of wrapper shares
        uint256 targetShares = initialShares / 2;
        vm.prank(vault);
        tokenWrapper.rebalanceATokens_CV(targetShares);

        // After rebalance, scaledBalance should equal targetShares
        uint256 scaledBalanceAfter = aTokenContract.scaledBalanceOf(vault);
        assertEq(scaledBalanceAfter, targetShares,
            "Scaled balance should equal target shares after rebalance, regardless of airdrops");

        // Rebalance to full wrapper balance
        vm.prank(vault);
        tokenWrapper.rebalanceATokens_CV(initialShares);

        scaledBalanceAfter = aTokenContract.scaledBalanceOf(vault);
        assertEq(scaledBalanceAfter, initialShares,
            "Scaled balance should equal full wrapper shares when rebalanced to full amount");

        // Rebalance to 0 (wrapper takes all aTokens)
        vm.prank(vault);
        tokenWrapper.rebalanceATokens_CV(0);

        scaledBalanceAfter = aTokenContract.scaledBalanceOf(vault);
        assertEq(scaledBalanceAfter, 0, "Scaled balance should be 0 after rebalancing to 0");
    }

    // Comprehensive test with multiple airdrops and arbitrary rebalances
    function test_fuzz_rebalanceATokens_complexScenario(uint256 seed) public {
        aave_createDeposit();

        address vault = alice;
        collateralVaultFactory.setIsCollateralVault(vault, true);

        // Initial setup
        deal(WSTETH, vault, 100e18);
        vm.startPrank(vault);
        IERC20(WSTETH).approve(address(tokenWrapper), 100e18);
        tokenWrapper.deposit(50e18, vault);
        IERC20(aToken).approve(address(tokenWrapper), type(uint256).max);
        vm.stopPrank();

        IAToken aTokenContract = IAToken(aToken);

        // Run 5 random operations
        for (uint256 i = 0; i < 5; i++) {
            uint256 op = uint256(keccak256(abi.encode(seed, i))) % 3;

            if (op == 0) {
                // Random wrapper share airdrop
                address dropper = makeAddr(string.concat("dropper", vm.toString(i)));
                uint256 dropAmount = bound(uint256(keccak256(abi.encode(seed, i, "amount"))), 1e18, 5e18);

                deal(WSTETH, dropper, dropAmount);
                vm.startPrank(dropper);
                IERC20(WSTETH).approve(address(tokenWrapper), dropAmount);
                tokenWrapper.deposit(dropAmount, dropper);
                tokenWrapper.transfer(vault, tokenWrapper.balanceOf(dropper));
                vm.stopPrank();
            } else if (op == 1) {
                // Random aToken airdrop
                address dropper = makeAddr(string.concat("aDropper", vm.toString(i)));
                uint256 dropAmount = bound(uint256(keccak256(abi.encode(seed, i, "aAmount"))), 1e18, 5e18);

                deal(WSTETH, dropper, dropAmount);
                vm.startPrank(dropper);
                IERC20(WSTETH).approve(address(tokenWrapper), dropAmount);
                tokenWrapper.deposit(dropAmount, dropper);
                tokenWrapper.redeem(tokenWrapper.balanceOf(dropper), dropper, dropper);
                IERC20(aToken).transfer(vault, IERC20(aToken).balanceOf(dropper));
                vm.stopPrank();
            }

            // After each operation, rebalance to a random amount <= wrapper balance
            uint256 vaultShares = tokenWrapper.balanceOf(vault);
            uint256 targetRebalance = bound(uint256(keccak256(abi.encode(seed, i, "rebalance"))), 0, vaultShares);

            vm.prank(vault);
            tokenWrapper.rebalanceATokens_CV(targetRebalance);

            // Verify the invariant
            assertEq(
                aTokenContract.scaledBalanceOf(vault),
                targetRebalance,
                string.concat("Iteration ", vm.toString(i), ": Scaled balance != rebalance target")
            );
        }
    }

    // Test reward claiming functionality

    function test_claimReward_accessControl() public {
        // Non-owner should not be able to claim rewards
        address mockRewardToken = makeAddr("mockRewardToken");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        tokenWrapper.claimReward(alice, mockRewardToken);
    }

    function test_claimReward_multipleRewardTokens() public {
        // Test claiming multiple different reward tokens through the Aave rewards system
        address rewardToken1 = makeAddr("rewardToken1");
        address rewardToken2 = makeAddr("rewardToken2");

        // Claim first reward token (only owner can claim)
        vm.prank(address(this));
        uint256 claimed1 = tokenWrapper.claimReward(alice, rewardToken1);

        // Claim second reward token
        vm.prank(address(this));
        uint256 claimed2 = tokenWrapper.claimReward(bob, rewardToken2);

        // Both should return 0 without emission setup, but function should not revert
        assertEq(claimed1, 0, "Should claim 0 for first reward token");
        assertEq(claimed2, 0, "Should claim 0 for second reward token");
    }

    // Helper functions for reward testing

    function _setupTestEnvironment(
        uint256 depositAmount,
        uint32 emissionEnd,
        uint88 emissionPerSecond,
        uint32 waitDuration
    ) internal returns (TestEnv memory) {
        TestEnv memory env;
        env.depositAmount = bound(depositAmount, 1 ether, type(uint96).max);
        env.emissionEnd = uint32(bound(emissionEnd, vm.getBlockTimestamp(), 365 days * 100));
        uint32 endTimestamp = uint32(bound(waitDuration, vm.getBlockTimestamp(), 365 days * 100));
        env.emissionDuration = env.emissionEnd > endTimestamp
            ? endTimestamp - uint32(vm.getBlockTimestamp())
            : env.emissionEnd - uint32(vm.getBlockTimestamp());
        env.emissionPerSecond = uint88(
            bound(
                emissionPerSecond,
                0,
                env.emissionDuration > 0 ? type(uint88).max / env.emissionDuration : type(uint88).max
            )
        );
        _setupEmission(env.emissionEnd, env.emissionPerSecond);
        _fundWrapper(env.depositAmount, user);

        vm.warp(endTimestamp);

        return env;
    }

    function _setupEmission(uint32 emissionEnd, uint88 emissionPerSecond) internal {
        RewardsDataTypes.RewardsConfigInput[] memory config = new RewardsDataTypes.RewardsConfigInput[](1);
        config[0] = RewardsDataTypes.RewardsConfigInput(
            emissionPerSecond,
            0, // totalSupply is overwritten internally
            emissionEnd,
            tokenWrapper.aToken(), // Use our wrapper's aToken
            rewardToken,
            ITransferStrategyBase(strategy),
            AggregatorInterface(address(2))
        );

        // configure asset
        vm.prank(emissionAdmin);
        contracts.emissionManager.configureAssets(config);

        // fund admin & approve transfers to allow claiming
        uint256 fundsToEmit = (emissionEnd - vm.getBlockTimestamp()) * emissionPerSecond;
        deal(rewardToken, emissionAdmin, fundsToEmit, true);
        vm.prank(emissionAdmin);
        IERC20(rewardToken).approve(address(strategy), fundsToEmit);
    }

    /**
     * @dev funds the given user with the wrapper tokens by depositing underlying.
     * This creates aToken balance for the wrapper and gives user wrapper shares.
     */
    function _fundWrapper(uint256 amount, address receiver) internal {
        // Give user underlying tokens
        deal(WSTETH, receiver, amount);

        // User deposits to wrapper (this creates aToken balance)
        vm.prank(receiver);
        IERC20(WSTETH).approve(address(tokenWrapper), amount);
        vm.prank(receiver);
        tokenWrapper.deposit(amount, receiver);
    }

    function _getRewardTokens() internal view returns (address[] memory) {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = rewardToken;
        return rewardTokens;
    }

    // Simple test without fuzzing to avoid supply cap issues
    function test_claimReward_withActualAaveRewards() public {
        // Use fixed reasonable values to avoid supply cap issues
        uint256 depositAmount = 1 ether;
        uint32 emissionEnd = uint32(vm.getBlockTimestamp() + 1 days);
        uint88 emissionPerSecond = 1 ether;
        uint32 waitDuration = uint32(vm.getBlockTimestamp() + 1 hours);

        _setupTestEnvironment(
            depositAmount,
            emissionEnd,
            emissionPerSecond,
            waitDuration
        );

        // Check that wrapper has aToken balance (from user deposits)
        uint256 wrapperATokenBalance = IERC20(tokenWrapper.aToken()).balanceOf(address(tokenWrapper));
        assertTrue(wrapperATokenBalance > 0, "Wrapper should have aToken balance from deposits");

        // Check claimable rewards before claiming
        address[] memory assets = new address[](1);
        assets[0] = tokenWrapper.aToken();
        uint256 claimableBefore = IRewardsController(contracts.rewardsControllerProxy)
            .getUserRewards(assets, address(tokenWrapper), rewardToken);

        // Should have some rewards after time passed
        assertTrue(claimableBefore > 0, "Should have some claimable rewards after time passed");

        // Claim rewards to alice
        uint256 aliceBalanceBefore = IERC20(rewardToken).balanceOf(alice);
        vm.prank(address(this)); // owner claims
        uint256 claimed = tokenWrapper.claimReward(alice, rewardToken);

        // Verify rewards were claimed and transferred to alice
        assertEq(claimed, claimableBefore, "Should claim all available rewards");
        assertEq(
            IERC20(rewardToken).balanceOf(alice),
            aliceBalanceBefore + claimed,
            "Alice should receive the claimed rewards"
        );

        // Verify subsequent claim returns 0 (rewards were already claimed)
        vm.prank(address(this));
        uint256 claimedAgain = tokenWrapper.claimReward(bob, rewardToken);
        assertEq(claimedAgain, 0, "Should claim 0 rewards after already claiming");
    }

    function test_update_pauseBlocksAllTransfers() public {
        uint256 amount = 1 ether;
        deal(WSTETH, address(this), amount);
        IERC20(WSTETH).approve(address(tokenWrapper), amount);

        tokenWrapper.deposit(amount, address(this));

        // Set approval for transferFrom test before pausing
        tokenWrapper.approve(address(this), amount / 2);

        tokenWrapper.pause();

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        tokenWrapper.transfer(alice, amount / 2);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        tokenWrapper.transferFrom(address(this), alice, amount / 2);

        vm.prank(alice);
        deal(WSTETH, alice, amount);
        vm.prank(alice);
        IERC20(WSTETH).approve(address(tokenWrapper), amount);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        tokenWrapper.deposit(amount, alice);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        tokenWrapper.redeem(amount / 2, address(this), address(this));
    }

    function test_burnShares_CV_pauseProtection() public {
        address vault = makeAddr("vault");
        collateralVaultFactory.setIsCollateralVault(vault, true);

        vm.startPrank(vault);

        uint256 amount = 1 ether;
        deal(WSTETH, vault, amount);
        IERC20(WSTETH).approve(address(tokenWrapper), amount);

        tokenWrapper.deposit(amount, vault);
        uint256 sharesToBurn = tokenWrapper.balanceOf(vault) / 2;

        vm.stopPrank();

        tokenWrapper.pause();

        vm.prank(vault);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        tokenWrapper.burnShares_CV(sharesToBurn);
    }

    function test_rebalanceATokens_CV_pauseProtection() public {
        address vault = makeAddr("vault");
        collateralVaultFactory.setIsCollateralVault(vault, true);

        vm.startPrank(vault);

        uint256 amount = 1 ether;
        deal(WSTETH, vault, amount);
        IERC20(WSTETH).approve(address(tokenWrapper), amount);

        tokenWrapper.deposit(amount, vault);
        uint256 sharesToRebalance = tokenWrapper.balanceOf(vault);

        vm.stopPrank();

        tokenWrapper.pause();

        vm.prank(vault);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        tokenWrapper.rebalanceATokens_CV(sharesToRebalance);
    }

    function test_skim() public {
        uint256 amount = 1 ether;
        deal(WSTETH, address(tokenWrapper), amount);

        uint256 wrapperAssetBalanceBefore = IERC20(WSTETH).balanceOf(address(tokenWrapper));
        uint256 aliceSharesBefore = tokenWrapper.balanceOf(alice);
        uint256 wrapperATokenBalanceBefore = IERC20(aToken).balanceOf(address(tokenWrapper));

        assertEq(wrapperAssetBalanceBefore, amount, "Wrapper should have WSTETH balance");
        assertEq(aliceSharesBefore, 0, "Alice should have no shares initially");

        tokenWrapper.skim(alice);

        uint256 wrapperAssetBalanceAfter = IERC20(WSTETH).balanceOf(address(tokenWrapper));
        uint256 aliceSharesAfter = tokenWrapper.balanceOf(alice);
        uint256 wrapperATokenBalanceAfter = IERC20(aToken).balanceOf(address(tokenWrapper));

        assertEq(wrapperAssetBalanceAfter, 0, "Wrapper should have no WSTETH balance after skim");
        assertGt(aliceSharesAfter, 0, "Alice should receive wrapper shares");
        assertGt(wrapperATokenBalanceAfter, wrapperATokenBalanceBefore, "Wrapper should have more aTokens");
    }

    function test_skim_shares() public {
        uint snapshot = vm.snapshot();
        uint256 amount = 1 ether;
        a_deposit(amount);

        uint depositShares = tokenWrapper.balanceOf(alice);

        vm.revertTo(snapshot);

        deal(WSTETH, address(tokenWrapper), amount);
        tokenWrapper.skim(alice);

        assertEq(tokenWrapper.balanceOf(alice), depositShares, "Deposit and Skim should lead to same number of shares");
    }

    function test_skim_anyoneCanCall() public {
        deal(WSTETH, address(tokenWrapper), 1 ether);

        uint256 bobSharesBefore = tokenWrapper.balanceOf(bob);

        vm.prank(alice);
        tokenWrapper.skim(bob);

        uint256 bobSharesAfter = tokenWrapper.balanceOf(bob);
        assertGt(bobSharesAfter, bobSharesBefore, "Bob should receive wrapper shares from skim called by Alice");
    }

    function test_skim_revertOnZeroShares() public {
        vm.expectRevert(abi.encodeWithSignature("StaticATokenInvalidZeroShares()"));
        tokenWrapper.skim(alice);

        // Test 1 wei which should definitely result in 0 shares due to rounding
        deal(WSTETH, address(tokenWrapper), 1);

        vm.expectRevert(abi.encodeWithSignature("StaticATokenInvalidZeroShares()"));
        tokenWrapper.skim(alice);
    }
}
