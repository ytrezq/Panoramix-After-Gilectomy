// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.22;

import { Test } from "../lib/forge-std/src/Test.sol";

import { ReserveConfiguration } from "../lib/aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { DataTypes }            from "../lib/aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";
import { WadRayMath }           from "../lib/aave-v3-core/contracts/protocol/libraries/math/WadRayMath.sol";

import { Ethereum }  from "../lib/spark-address-registry/src/Ethereum.sol";
import { SparkLend } from "../lib/spark-address-registry/src/SparkLend.sol";

import { IACLManagerLike, IPoolLike, IScaledBalanceTokenLike } from "./interfaces/IAAVEV3.sol";

import { IERC20Like } from "./interfaces/Common.sol";

import { CapAutomator } from "../src/CapAutomator.sol";

contract CapAutomatorIntegrationTestsBase is Test {

    using WadRayMath for uint256;

    address internal constant POOL_ADDRESSES_PROVIDER = SparkLend.POOL_ADDRESSES_PROVIDER;
    address internal constant POOL                    = SparkLend.POOL;
    address internal constant POOL_CONFIG             = SparkLend.POOL_CONFIGURATOR;
    address internal constant DATA_PROVIDER           = SparkLend.PROTOCOL_DATA_PROVIDER;
    address internal constant ACL_MANAGER             = SparkLend.ACL_MANAGER;
    address internal constant SPARK_PROXY             = Ethereum.SPARK_PROXY;
    address internal constant CAP_AUTO_UPDATER        = Ethereum.ALM_RELAYER_MULTISIG;
    address internal constant WETH                    = Ethereum.WETH;
    address internal constant WBTC                    = Ethereum.WBTC;

    address internal user = makeAddr("user");

    address[] internal assets;

    CapAutomator internal capAutomator;

    IACLManagerLike internal aclManager = IACLManagerLike(ACL_MANAGER);
    IPoolLike       internal pool       = IPoolLike(POOL);

    function setUp() public {
        vm.createSelectFork(getChain("mainnet").rpcUrl, 18721430);

        vm.prank(SPARK_PROXY);
        capAutomator = new CapAutomator(POOL_ADDRESSES_PROVIDER, SPARK_PROXY, CAP_AUTO_UPDATER);

        vm.prank(SPARK_PROXY);
        aclManager.addRiskAdmin(address(capAutomator));

        assets = pool.getReservesList();
    }

    function _currentATokenSupply(
        DataTypes.ReserveData memory _reserveData
    ) internal view returns (uint256) {
        return
            (
                IScaledBalanceTokenLike(_reserveData.aTokenAddress).scaledTotalSupply()
                + _reserveData.accruedToTreasury
            ).rayMul(_reserveData.liquidityIndex)
            / 10 ** IERC20Like(_reserveData.aTokenAddress).decimals();
    }

    function currentBorrows(
        DataTypes.ReserveData memory _reserveData
    ) internal view returns (uint256) {
        return
            IERC20Like(_reserveData.variableDebtTokenAddress).totalSupply()
            / 10 ** IERC20Like(_reserveData.variableDebtTokenAddress).decimals();
    }

}

contract GeneralizedTests is CapAutomatorIntegrationTestsBase {

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    function test_E2E_increaseBorrowCap() external {
        for (uint256 i; i < assets.length; ++i) {
            DataTypes.ReserveData memory reserveData = pool.getReserveData(assets[i]);

            uint256 preIncreaseBorrowCap = reserveData.configuration.getBorrowCap();
            uint256 currentBorrow        = currentBorrows(reserveData);

            uint256 newMaxCap;
            uint256 newGap;

            if (preIncreaseBorrowCap != 0) {  // If there is a borrow cap, set config based on it
                uint256 preIncreaseBorrowGap = preIncreaseBorrowCap - currentBorrow;

                newMaxCap = preIncreaseBorrowCap * 2;  // Increase the max cap so cap increase is possible
                newGap    = preIncreaseBorrowGap * 2;  // Increase the gap so cap will be increased higher than the current cap
            } else if (currentBorrow != 0) {  // If there is unlimited borrowing, set config based on current borrows
                newMaxCap = currentBorrow * 4;
                // Set the gap to a value strictly less than the maxCap so that the cap can be increased by the gap instead
                // of being limited by the max cap.
                newGap    = currentBorrow * 2;
            } else {  // If there is no cap and no borrows, use arbitrary values for the config
                newMaxCap = 2_000;
                newGap    = 1_000;
            }

            vm.prank(SPARK_PROXY);
            capAutomator.setBorrowCapConfig({
                asset:            assets[i],
                max:              newMaxCap,
                gap:              newGap,
                increaseCooldown: 12 hours
            });

            (
                ,,,
                uint48 lastUpdateBlock,
                uint48 lastIncreaseTime
            ) = capAutomator.borrowCapConfigs(assets[i]);

            assertEq(lastUpdateBlock,  0);
            assertEq(lastIncreaseTime, 0);

            vm.prank(CAP_AUTO_UPDATER);
            capAutomator.exec(assets[i]);

            (
                ,,,
                lastUpdateBlock,
                lastIncreaseTime
            ) = capAutomator.borrowCapConfigs(assets[i]);

            assertEq(lastUpdateBlock,  block.number);
            assertEq(lastIncreaseTime, block.timestamp);

            uint256 postIncreaseBorrowCap
                = pool.getReserveData(assets[i]).configuration.getBorrowCap();

            assertEq(postIncreaseBorrowCap, currentBorrow + newGap);
        }
    }

    function test_E2E_decreaseBorrowCap() external {
        for (uint256 i; i < assets.length; ++i) {
            DataTypes.ReserveData memory reserveData = pool.getReserveData(assets[i]);

            uint256 preDecreaseBorrowCap = reserveData.configuration.getBorrowCap();

            // If there is a cap a decrease will be attempted, but if there is no cap, decrease is not possible
            if (preDecreaseBorrowCap == 0) continue;

            uint256 currentBorrow        = currentBorrows(reserveData);
            uint256 preDecreaseBorrowGap = preDecreaseBorrowCap - currentBorrow;

            uint256 newGap = preDecreaseBorrowGap / 3;

            vm.prank(SPARK_PROXY);
            capAutomator.setBorrowCapConfig({
                asset:            assets[i],
                max:              preDecreaseBorrowCap,
                gap:              newGap,
                increaseCooldown: 12 hours
            });

            (
                ,,,
                uint48 lastUpdateBlock,
                uint48 lastIncreaseTime
            ) = capAutomator.borrowCapConfigs(assets[i]);

            assertEq(lastUpdateBlock,  0);
            assertEq(lastIncreaseTime, 0);

            vm.prank(CAP_AUTO_UPDATER);
            capAutomator.exec(assets[i]);

            (
                ,,,
                lastUpdateBlock,
                lastIncreaseTime
            ) = capAutomator.borrowCapConfigs(assets[i]);

            assertEq(lastUpdateBlock,  block.number);
            assertEq(lastIncreaseTime, 0);

            uint256 postDecreaseBorrowCap
                = pool.getReserveData(assets[i]).configuration.getBorrowCap();

            assertEq(postDecreaseBorrowCap, currentBorrow + newGap);

            if (currentBorrow < 3) continue; // "> 0", but also so "/ 3" makes sense

            vm.roll(block.number + 1);

            uint256 borrowCapBelowState = currentBorrow / 3;

            vm.prank(SPARK_PROXY);
            capAutomator.setBorrowCapConfig({
                asset:            assets[i],
                max:              borrowCapBelowState,
                gap:              1,
                increaseCooldown: 12 hours
            });

            vm.prank(CAP_AUTO_UPDATER);
            capAutomator.exec(assets[i]);

            postDecreaseBorrowCap = pool.getReserveData(assets[i]).configuration.getBorrowCap();

            assertEq(postDecreaseBorrowCap, borrowCapBelowState);
        }
    }

    function test_E2E_increaseSupplyCap() external {
        for (uint256 i; i < assets.length; ++i) {
            DataTypes.ReserveData memory reserveData = pool.getReserveData(assets[i]);

            uint256 preIncreaseSupplyCap = reserveData.configuration.getSupplyCap();
            uint256 currentSupply        = _currentATokenSupply(reserveData);

            uint256 newMaxCap;
            uint256 newGap;

            if (preIncreaseSupplyCap != 0) {  // If there is a supply cap, set config based on it
                uint256 preIncreaseSupplyGap = preIncreaseSupplyCap - currentSupply;
                newMaxCap = preIncreaseSupplyCap * 2;  // Increase the max cap so cap increase is possible
                newGap    = preIncreaseSupplyGap * 2;  // Increase the gap so cap will be increased higher than the current cap
            } else if (currentSupply != 0) {  // If there is unlimited supplying, set config based on current supply
                newMaxCap = currentSupply * 4;
                // Set the gap to a value strictly less than the maxCap so that the cap can be increased by the gap instead
                // of being limited by the max cap.
                newGap    = currentSupply * 2;
            } else {  // If there is no cap and no supply, use arbitrary values for the config
                newMaxCap = 2_000;
                newGap    = 1_000;
            }

            vm.prank(SPARK_PROXY);
            capAutomator.setSupplyCapConfig({
                asset:            assets[i],
                max:              newMaxCap,
                gap:              newGap,
                increaseCooldown: 12 hours
            });

            (
                ,,,
                uint48 lastUpdateBlock,
                uint48 lastIncreaseTime
            ) = capAutomator.supplyCapConfigs(assets[i]);

            assertEq(lastUpdateBlock,  0);
            assertEq(lastIncreaseTime, 0);

            vm.prank(CAP_AUTO_UPDATER);
            capAutomator.exec(assets[i]);

            (
                ,,,
                lastUpdateBlock,
                lastIncreaseTime
            ) = capAutomator.supplyCapConfigs(assets[i]);

            assertEq(lastUpdateBlock,  block.number);
            assertEq(lastIncreaseTime, block.timestamp);

            uint256 postIncreaseSupplyCap
                = pool.getReserveData(assets[i]).configuration.getSupplyCap();

            assertEq(postIncreaseSupplyCap, currentSupply + newGap);
        }
    }

    function test_E2E_decreaseSupplyCap() external {
        for (uint256 i; i < assets.length; ++i) {
            DataTypes.ReserveData memory reserveData = pool.getReserveData(assets[i]);

            uint256 preDecreaseSupplyCap = reserveData.configuration.getSupplyCap();

            // If there is a cap a decrease will be attempted, but if there is no cap, decrease is not possible
            if (preDecreaseSupplyCap == 0) continue;

            uint256 currentSupply        = _currentATokenSupply(reserveData);
            uint256 preDecreaseSupplyGap = preDecreaseSupplyCap - currentSupply;

            uint256 newGap = preDecreaseSupplyGap / 3;

            vm.prank(SPARK_PROXY);
            capAutomator.setSupplyCapConfig({
                asset:            assets[i],
                max:              preDecreaseSupplyCap,
                gap:              newGap,
                increaseCooldown: 12 hours
            });

            (
                ,,,
                uint48 lastUpdateBlock,
                uint48 lastIncreaseTime
            ) = capAutomator.supplyCapConfigs(assets[i]);

            assertEq(lastUpdateBlock,  0);
            assertEq(lastIncreaseTime, 0);

            vm.prank(CAP_AUTO_UPDATER);
            capAutomator.exec(assets[i]);

            (
                ,,,
                lastUpdateBlock,
                lastIncreaseTime
            ) = capAutomator.supplyCapConfigs(assets[i]);

            assertEq(lastUpdateBlock,  block.number);
            assertEq(lastIncreaseTime, 0);

            uint256 postDecreaseSupplyCap
                = pool.getReserveData(assets[i]).configuration.getSupplyCap();

            assertEq(postDecreaseSupplyCap, currentSupply + newGap);

            if (currentSupply < 3) continue; // "> 0", but also so "/ 3" makes sense

            vm.roll(block.number + 1);

            uint256 supplyCapBelowState = currentSupply / 3;

            vm.prank(SPARK_PROXY);
            capAutomator.setSupplyCapConfig({
                asset:            assets[i],
                max:              supplyCapBelowState,
                gap:              1,
                increaseCooldown: 12 hours
            });

            vm.prank(CAP_AUTO_UPDATER);
            capAutomator.exec(assets[i]);

            postDecreaseSupplyCap = pool.getReserveData(assets[i]).configuration.getSupplyCap();

            assertEq(postDecreaseSupplyCap, supplyCapBelowState);
        }
    }

}

contract ConcreteTests is CapAutomatorIntegrationTestsBase {

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath           for uint256;

    uint256 internal constant USERS_STASH = 6_000e8;

    function test_E2E_supply_wbtc() external {
        assertEq(IERC20Like(WBTC).decimals(), 8);

        DataTypes.ReserveData memory wbtcReserveData = pool.getReserveData(WBTC);

        // Confirm initial supply cap
        assertEq(wbtcReserveData.configuration.getSupplyCap(), 3_000);

        // Confirm initial WBTC supply
        uint256 initialSupply = _currentATokenSupply(wbtcReserveData);

        assertEq(initialSupply, 750);

        vm.prank(SPARK_PROXY);
        capAutomator.setSupplyCapConfig({
            asset:            WBTC,
            max:              6_000,
            gap:              500,
            increaseCooldown: 12 hours
        });

        vm.startPrank(user);

        deal(WBTC, user, USERS_STASH);
        IERC20Like(WBTC).approve(POOL, USERS_STASH);

        pool.supply(WBTC, 2_000e8, user, 0);

        vm.stopPrank();

        // Confirm that WBTC supply cap didn't change yet
        assertEq(pool.getReserveData(WBTC).configuration.getSupplyCap(), 3_000);

        vm.prank(CAP_AUTO_UPDATER);
        capAutomator.execSupply(WBTC);

        // Confirm correct WBTC supply cap increase
        // initialSupply + newlySupplied + gap = 750 + 2_000 + 500 = 3_250
        assertEq(pool.getReserveData(WBTC).configuration.getSupplyCap(), 3_250);

        vm.roll(block.number + 1);
        vm.prank(user);
        pool.supply(WBTC, 250e8, user, 0);

        // Check the cap is not changing before cooldown passes
        vm.prank(CAP_AUTO_UPDATER);
        capAutomator.execSupply(WBTC);

        assertEq(pool.getReserveData(WBTC).configuration.getSupplyCap(), 3_250);

        // Check correct cap increase after cooldown
        skip(24 hours);
        vm.prank(CAP_AUTO_UPDATER);
        capAutomator.execSupply(WBTC);

        // initialSupply + suppliedBefore + newlySupplied + gap = 750 + 2_000 + 250 + 500 = 3_500
        assertEq(pool.getReserveData(WBTC).configuration.getSupplyCap(), 3_500);

        vm.roll(block.number + 1);
        vm.prank(user);
        pool.withdraw(WBTC, 125e8, user);

        // Check correct cap decrease (without cooldown)
        vm.prank(CAP_AUTO_UPDATER);
        capAutomator.execSupply(WBTC);

        // previousSupply - justWithdrawn + gap = 3_000 - 125 + 500 = 3_375
        assertEq(pool.getReserveData(WBTC).configuration.getSupplyCap(), 3_375);

        vm.prank(user);
        pool.withdraw(WBTC, 125e8, user);

        // Check the cap is not changing in the same block
        vm.prank(CAP_AUTO_UPDATER);
        capAutomator.execSupply(WBTC);

        assertEq(pool.getReserveData(WBTC).configuration.getSupplyCap(), 3_375);

        // Check correct cap decrease after block changes
        vm.roll(block.number + 1);
        vm.prank(CAP_AUTO_UPDATER);
        capAutomator.execSupply(WBTC);

        // previousSupply - justWithdrawn + gap = 2_875 - 125 + 500 = 3_250
        assertEq(pool.getReserveData(WBTC).configuration.getSupplyCap(), 3_250);

        // Check that the supply cap can be decreased below current supply
        vm.prank(SPARK_PROXY);
        capAutomator.setSupplyCapConfig({
            asset:            WBTC,
            max:              1_000,
            gap:              100,
            increaseCooldown: 12 hours
        });

        vm.roll(block.number + 1);
        vm.prank(CAP_AUTO_UPDATER);
        capAutomator.execSupply(WBTC);

        // initialSupply + suppliedInTest - withdrawnInTest = 750 + 2_000 + 250 - 125 - 125 = 750 + 2_250 - 250 = 2_750
        assertEq(_currentATokenSupply(pool.getReserveData(WBTC)),        2_750);
        assertEq(pool.getReserveData(WBTC).configuration.getSupplyCap(), 1_000);

        vm.expectRevert(bytes("51"));  // SUPPLY_CAP_EXCEEDED
        vm.prank(user);
        pool.supply(WBTC, 1, user, 0);
    }

    function test_E2E_borrow_weth() external {
        assertEq(IERC20Like(WETH).decimals(), 18);

        DataTypes.ReserveData memory wethReserveData = pool.getReserveData(WETH);

        // Confirm initial borrow cap
        uint256 initialBorrowCap = wethReserveData.configuration.getBorrowCap();

        assertEq(initialBorrowCap, 1_400_000);

        // Confirm initial borrows
        uint256 initialBorrows = currentBorrows(wethReserveData);

        assertEq(initialBorrows, 126_520);

        vm.prank(SPARK_PROXY);
        capAutomator.setBorrowCapConfig({
            asset:            WETH,
            max:              2_000_000,
            gap:              100_000,
            increaseCooldown: 12 hours
        });

        vm.startPrank(user);

        deal(WBTC, user, USERS_STASH);
        IERC20Like(WBTC).approve(POOL, USERS_STASH);

        pool.supply(WBTC, 2_000e8, user, 0);

        vm.stopPrank();

        // Check correct cap decrease
        vm.prank(CAP_AUTO_UPDATER);
        capAutomator.execBorrow(WETH);

        // totalDebt + gap = 126_520 + 100_000 = 226_520
        assertEq(pool.getReserveData(WETH).configuration.getBorrowCap(), 226_520);

        vm.prank(user);
        pool.borrow(WETH, 480e18, 2 /* variable rate mode */, 0, user);

        // Check that another cap change is not possible in the same block
        vm.prank(CAP_AUTO_UPDATER);
        capAutomator.execBorrow(WETH);

        assertEq(pool.getReserveData(WETH).configuration.getBorrowCap(), 226_520);

        // Check correct cap increase in the new block
        vm.roll(block.number + 1);
        vm.prank(CAP_AUTO_UPDATER);
        capAutomator.execBorrow(WETH);

        // totalDebt + gap = initialBorrows + newlyBorrowed + gap = 126_520 + 480 + 100_000 = 227_000
        assertEq(pool.getReserveData(WETH).configuration.getBorrowCap(), 227_000);

        vm.startPrank(user);
        IERC20Like(WETH).approve(POOL, 50e18);
        pool.repay(WETH, 50e18, 2 /* variable rate mode */, user);
        vm.stopPrank();

        // Check correct cap decrease without cooldown passing
        vm.roll(block.number + 1);
        vm.prank(CAP_AUTO_UPDATER);
        capAutomator.execBorrow(WETH);

        // totalDebt + gap = initialBorrows + previouslyBorrowed - newlyRepaid + gap = 126_520 + 480 - 50 + 100_000 = 226_950
        assertEq(pool.getReserveData(WETH).configuration.getBorrowCap(), 226_950);

        vm.prank(user);
        pool.borrow(WETH, 150e18, 2 /* variable rate mode */, 0, user);

        vm.roll(block.number + 1);
        // Check the cap is not increasing before cooldown passes
        vm.prank(CAP_AUTO_UPDATER);
        capAutomator.execBorrow(WETH);

        assertEq(pool.getReserveData(WETH).configuration.getBorrowCap(), 226_950);

        // Check correct cap increase after cooldown
        skip(24 hours);
        vm.prank(CAP_AUTO_UPDATER);
        capAutomator.execBorrow(WETH);

        // totalDebt + gap = initialBorrows + previouslyBorrowed - previouslyRepaid + justBorrowed + debtAccruedIn24h + gap
        // = 126_520 + 480 - 50 + 150 + 10 + 100_000 = 227_000
        assertEq(pool.getReserveData(WETH).configuration.getBorrowCap(), 227_110);

        // Check that the borrow cap can be decreased below current borrows
        vm.prank(SPARK_PROXY);
        capAutomator.setBorrowCapConfig({
            asset:            WETH,
            max:              100_000,
            gap:              100,
            increaseCooldown: 12 hours
        });

        vm.roll(block.number + 1);
        vm.prank(CAP_AUTO_UPDATER);
        capAutomator.execBorrow(WETH);

        assertEq(currentBorrows(pool.getReserveData(WETH)), 127_110);

        // initialBorrows + borrowedInTest - repaidInTest + debtAccruedIn24h
        // = 126_520 + 480 + 150 - 50 + 10 = 227_000
        assertEq(pool.getReserveData(WETH).configuration.getBorrowCap(), 100_000);

        vm.expectRevert(bytes("50"));  // BORROW_CAP_EXCEEDED
        vm.prank(user);
        pool.borrow(WETH, 1, 2 /* variable rate mode */, 0, user);
    }

    function test_E2E_flashloan() external {
        DataTypes.ReserveData memory initialReserveData = pool.getReserveData(WBTC);

        // Confirm initial state
        assertEq(IERC20Like(WBTC).decimals(),                     8);
        assertEq(_currentATokenSupply(initialReserveData),        750);
        assertEq(initialReserveData.configuration.getSupplyCap(), 3_000);

        vm.prank(SPARK_PROXY);
        capAutomator.setSupplyCapConfig({
            asset:            WBTC,
            max:              10_000,
            gap:              50,
            increaseCooldown: 12 hours
        });

        vm.prank(CAP_AUTO_UPDATER);
        capAutomator.execSupply(WBTC);

        vm.roll(block.number + 1);
        skip(12 hours + 1);

        // Confirm new, tightly set supply cap
        assertEq(pool.getReserveData(WBTC).configuration.getSupplyCap(), 800);

        pool.flashLoanSimple(
            address(this),
            WBTC,
            100e8,
            abi.encode(address(pool)),
            0
        );

        // Confirm the cap increase even though the supply effectively didn't change
        DataTypes.ReserveData memory postFlashloanReserveData = pool.getReserveData(WBTC);

        assertEq(_currentATokenSupply(postFlashloanReserveData),        750);
        assertEq(postFlashloanReserveData.configuration.getSupplyCap(), 850);

        // Confirm that in the next block, before increase cooldown passes, cap can be decreased
        vm.roll(block.number + 1);
        vm.prank(CAP_AUTO_UPDATER);
        capAutomator.execSupply(WBTC);

        assertEq(pool.getReserveData(WBTC).configuration.getSupplyCap(), 800);

        vm.roll(block.number + 1);
        skip(6 hours);

        deal(WBTC, address(this), 40e8);
        IERC20Like(WBTC).approve(address(pool), 40e8);
        pool.supply(WBTC, 40e8, address(this), 0);

        // Confirm that after some time, smaller than cooldown, cap cannot be increased
        vm.prank(CAP_AUTO_UPDATER);
        capAutomator.execSupply(WBTC);

        assertEq(pool.getReserveData(WBTC).configuration.getSupplyCap(), 800);

        skip(6 hours + 1);

        // Confirm that after sufficient time passes, cap can be increased again
        vm.prank(CAP_AUTO_UPDATER);
        capAutomator.execSupply(WBTC);

        assertEq(pool.getReserveData(WBTC).configuration.getSupplyCap(), 840);
    }

    // Called back from the flashloan
    function executeOperation(
        address          asset,
        uint256          amount,
        uint256,
        address,
        bytes   calldata
    ) external returns (bool) {
        DataTypes.ReserveData memory initialReserveData = pool.getReserveData(WBTC);

        uint256 currentExactSupply =
            (
                IScaledBalanceTokenLike(initialReserveData.aTokenAddress).scaledTotalSupply()
                + initialReserveData.accruedToTreasury
            ).rayMul(initialReserveData.liquidityIndex);

        uint256 dust = currentExactSupply % 1e8;

        // Confirm that at the beginning the max possible supply is the gap value minus the dust
        assertEq(
            initialReserveData.configuration.getSupplyCap() * 1e8 - currentExactSupply,
            50e8 - dust
        );

        // Supply additional funds to the pool, bring the supply closer to the cap than the gap
        IERC20Like(asset).approve(address(pool), 50e8 - dust);
        pool.supply(WBTC, 50e8 - dust, address(this), 0);

        // Confirm previous cap before the update
        // initialSupply + gap = (750 + dust) + 50 = 800
        assertEq(initialReserveData.configuration.getSupplyCap(), 800);

        // Confirm the cap can be correctly increased
        // initialSupply + maxPossibleSupplyBeforeCapIncrease + gap = (750 + dust) + (50 - dust) + 50 = 850
        vm.prank(CAP_AUTO_UPDATER);
        capAutomator.execSupply(WBTC);

        assertEq(pool.getReserveData(WBTC).configuration.getSupplyCap(), 850);

        // Supply more funds to attempt a second cap increase
        IERC20Like(asset).approve(address(pool), 50e8);
        pool.supply(WBTC, 50e8, address(this), 0);

        // Confirm the cap cannot be increased twice
        // initialSupply + totalSuppliedFunds + gap = (750 + dust) + (100 - dust) + 50 = 900
        vm.prank(CAP_AUTO_UPDATER);
        capAutomator.execSupply(WBTC);

        assertEq(pool.getReserveData(WBTC).configuration.getSupplyCap(), 850);

        // Withdraw funds to pay back the flashloan
        pool.withdraw(WBTC, 100e8 - dust, address(this));

        // Confirm the cap cannot be decreased in the same block, even though the supply came back to the initial state
        // initialSupply + totalSuppliedFunds - withdrawnFunds + gap = (750 + dust) + (100 - dust) - (100 - dust) + 50 = 800
        vm.prank(CAP_AUTO_UPDATER);
        capAutomator.execSupply(WBTC);

        assertEq(pool.getReserveData(WBTC).configuration.getSupplyCap(), 850);

        IERC20Like(asset).approve(address(pool), amount);

        return true;
    }

}
