// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SimpleStrategy} from "../../../src/periphery/strategies/SimpleStrategy.sol";
import {BaseStrategy} from "../../../src/periphery/strategies/BaseStrategy.sol";
import {IBaseStrategy} from "../../../src/periphery/interface/IBaseStrategy.sol";
import {StrategyType} from "../../../src/interface/IStrategyTemplate.sol";
import {ERC20Mock} from "../../mock/ERC20Mock.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC4626} from "@openzeppelin-contracts/interfaces/IERC4626.sol";
import {PeripheryRolesLib} from "../../../src/periphery/lib/PeripheryRolesLib.sol";

// Mock vault that implements IERC4626
contract MockVault {
    address public immutable asset;

    constructor(address _asset) {
        asset = _asset;
    }
}

contract SimpleStrategyUnitTest is Test {
    SimpleStrategy strategy;
    ERC20Mock asset;
    address admin;
    address vault;
    address user;

    event AllocateFunds(uint256 amount);
    event DeallocateFunds(uint256 amount);
    event StrategyWithdraw(uint256 amount);

    function setUp() public {
        admin = makeAddr("admin");
        user = makeAddr("user");

        asset = new ERC20Mock();
        MockVault mockVault = new MockVault(address(asset));
        vault = address(mockVault);

        strategy = deployAndInitializeStrategy();
    }

    function deployAndInitializeStrategy() internal returns (SimpleStrategy) {
        SimpleStrategy impl = new SimpleStrategy();

        // Create proxy and initialize
        bytes memory initData = abi.encodeWithSelector(BaseStrategy.initialize.selector, admin, vault);

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        return SimpleStrategy(address(proxy));
    }

    function setupStrategyWithVaultAndTokens() internal {
        // Mint tokens to vault so it can transfer to strategy
        asset.mint(vault, 1000e18);
        // Approve strategy to spend vault's tokens
        vm.prank(vault);
        asset.approve(address(strategy), 1000e18);
    }

    function testConstructor() public view {
        assertEq(strategy.asset(), address(asset));
        assertTrue(strategy.hasRole(PeripheryRolesLib.STRATEGY_ADMIN, admin));
        // vault is set in initialize
        assertEq(strategy.getVault(), vault);
    }

    function testAllocateFunds() public {
        setupStrategyWithVaultAndTokens();

        bytes memory data = abi.encode(1000e18);

        vm.expectEmit(true, true, true, true);
        emit AllocateFunds(1000e18);

        vm.prank(vault);
        uint256 allocated = strategy.allocateFunds(data);

        assertEq(allocated, 1000e18);
        assertEq(strategy.totalAllocatedValue(), 1000e18);
        assertEq(asset.balanceOf(address(strategy)), 1000e18);
    }

    function testDeallocateFunds() public {
        setupStrategyWithVaultAndTokens();

        // First allocate some funds
        vm.prank(vault);
        strategy.allocateFunds(abi.encode(1000e18));

        bytes memory data = abi.encode(1000e18);

        vm.expectEmit(true, true, true, true);
        emit DeallocateFunds(1000e18);

        vm.prank(vault);
        uint256 deallocated = strategy.deallocateFunds(data);

        assertEq(deallocated, 1000e18);
        assertEq(strategy.totalAllocatedValue(), 0);
        assertEq(asset.balanceOf(vault), 1000e18);
    }

    function testOnWithdraw() public {
        setupStrategyWithVaultAndTokens();

        // First allocate some funds
        vm.prank(vault);
        strategy.allocateFunds(abi.encode(1000e18));

        vm.expectEmit(true, true, true, true);
        emit StrategyWithdraw(50e18);

        vm.prank(vault);
        uint256 withdrawn = strategy.onWithdraw(50e18);

        assertEq(withdrawn, 50e18);
        assertEq(strategy.totalAllocatedValue(), 950e18);
        assertEq(asset.balanceOf(vault), 50e18);
    }

    function testMaxAllocation() public view {
        assertEq(strategy.maxAllocation(), type(uint256).max);
    }

    function testMaxWithdraw() public {
        // Initially no allocation
        assertEq(strategy.maxWithdraw(), 0);

        // After allocation
        setupStrategyWithVaultAndTokens();
        vm.prank(vault);
        strategy.allocateFunds(abi.encode(1000e18));

        assertEq(strategy.maxWithdraw(), 1000e18);
    }

    function testStrategyType() public view {
        assertEq(uint8(strategy.strategyType()), uint8(StrategyType.ATOMIC));
    }

    function testUnauthorizedAccess() public {
        vm.prank(user);
        vm.expectRevert(IBaseStrategy.UnauthorizedVault.selector);
        strategy.allocateFunds(abi.encode(100e18));

        vm.prank(user);
        vm.expectRevert(IBaseStrategy.UnauthorizedVault.selector);
        strategy.deallocateFunds(abi.encode(100e18));

        vm.prank(user);
        vm.expectRevert(IBaseStrategy.UnauthorizedVault.selector);
        strategy.onWithdraw(100e18);
    }

    function testInsufficientBalance() public {
        vm.prank(admin);
        strategy.setMaxWithdraw(2000e18);
        vm.prank(vault);
        vm.expectRevert(IBaseStrategy.MaxWithdrawAmountExceeded.selector);
        strategy.onWithdraw(1000e18); // More than allocated
    }

    function testSetMaxWithdrawEvent() public {
        // The initial maxWithdraw is type(uint256).max, so we expect that as the old value
        vm.expectEmit(true, true, true, true);
        emit IBaseStrategy.MaxWithdrawUpdated(type(uint256).max, 1000e18);

        vm.prank(admin);
        strategy.setMaxWithdraw(1000e18);
    }

    function testSetMaxWithdrawEventMultipleChanges() public {
        // First change: from type(uint256).max to 1000e18
        vm.expectEmit(true, true, true, true);
        emit IBaseStrategy.MaxWithdrawUpdated(type(uint256).max, 1000e18);

        vm.prank(admin);
        strategy.setMaxWithdraw(1000e18);

        // Second change: from 1000e18 to 2000e18
        vm.expectEmit(true, true, true, true);
        emit IBaseStrategy.MaxWithdrawUpdated(1000e18, 2000e18);

        vm.prank(admin);
        strategy.setMaxWithdraw(2000e18);
    }

    function testInsufficientAllocatedAmountDeallocate() public {
        setupStrategyWithVaultAndTokens();

        // First allocate some funds
        vm.prank(vault);
        strategy.allocateFunds(abi.encode(500e18));

        // Try to deallocate more than allocated
        vm.prank(vault);
        vm.expectRevert(IBaseStrategy.InsufficientAllocatedAmount.selector);
        strategy.deallocateFunds(abi.encode(1000e18)); // More than allocated
    }

    function testEmergencyRecover() public {
        // Create a different token for emergency recovery
        ERC20Mock otherToken = new ERC20Mock();
        otherToken.mint(address(strategy), 100e18);

        uint256 initialBalance = otherToken.balanceOf(admin);

        vm.prank(admin);
        strategy.rescueToken(address(otherToken), 50e18);

        assertEq(otherToken.balanceOf(admin), initialBalance + 50e18);
    }

    function testEmergencyRecoverUnauthorized() public {
        // Create a different token for unauthorized test
        ERC20Mock otherToken = new ERC20Mock();

        vm.prank(user);
        vm.expectRevert();
        strategy.rescueToken(address(otherToken), 50e18);
    }

    function testEmergencyRecoverAssetToken() public {
        // Mint some tokens to the strategy
        asset.mint(address(strategy), 100e18);

        // Try to recover the strategy's asset token (should fail)
        vm.prank(admin);
        vm.expectRevert(IBaseStrategy.InvalidAsset.selector);
        strategy.rescueToken(address(asset), 50e18);
    }

    function testTotalAllocatedValue() public {
        // Initially should return 0
        assertEq(strategy.totalAllocatedValue(), 0);

        // Allocate some funds
        setupStrategyWithVaultAndTokens();
        vm.prank(vault);
        strategy.allocateFunds(abi.encode(1000e18));

        // Should return allocated amount
        assertEq(strategy.totalAllocatedValue(), 1000e18);
    }

    function testPause() public {
        // Initially not paused
        assertFalse(strategy.paused());

        // Admin can pause
        vm.prank(admin);
        strategy.pause();

        // Should be paused
        assertTrue(strategy.paused());
    }

    function testUnpause() public {
        // Pause first
        vm.prank(admin);
        strategy.pause();
        assertTrue(strategy.paused());

        // Admin can unpause
        vm.prank(admin);
        strategy.unpause();

        // Should not be paused
        assertFalse(strategy.paused());
    }

    function testPauseUnauthorized() public {
        // Non-admin cannot pause
        vm.prank(user);
        vm.expectRevert();
        strategy.pause();
    }

    function testUnpauseUnauthorized() public {
        // Pause first
        vm.prank(admin);
        strategy.pause();

        // Non-admin cannot unpause
        vm.prank(user);
        vm.expectRevert();
        strategy.unpause();
    }

    function testPausePreventsOperations() public {
        setupStrategyWithVaultAndTokens();

        // Pause the strategy
        vm.prank(admin);
        strategy.pause();

        // Should not be able to allocate funds when paused
        vm.prank(vault);
        vm.expectRevert();
        strategy.allocateFunds(abi.encode(1000e18));

        // Should not be able to deallocate funds when paused
        vm.prank(vault);
        vm.expectRevert();
        strategy.deallocateFunds(abi.encode(500e18));

        // Should not be able to withdraw when paused
        vm.prank(vault);
        vm.expectRevert();
        strategy.onWithdraw(500e18);
    }
}
