// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MultisigStrategy} from "../../../src/periphery/strategies/MultisigStrategy.sol";
import {IBaseStrategy} from "../../../src/periphery/interface/IBaseStrategy.sol";
import {PositionAccountingLib} from "../../../src/periphery/lib/PositionAccountingLib.sol";
import {PeripheryRolesLib} from "../../../src/periphery/lib/PeripheryRolesLib.sol";
import {StrategyType} from "../../../src/interface/IStrategyTemplate.sol";
import {ERC20Mock} from "../../mock/ERC20Mock.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC4626} from "@openzeppelin-contracts/interfaces/IERC4626.sol";
import {console2 as console} from "forge-std/console2.sol";

// Mock vault that implements IERC4626
contract MockVault {
    address public immutable asset;

    constructor(address asset_) {
        asset = asset_;
    }
}

contract MultisigStrategyUnitTest is Test {
    MultisigStrategy public strategy;
    ERC20Mock public asset;
    MockVault public vault;
    address public admin;
    address public multisig;
    address public operator;

    event MultiSigSet(address indexed multiSig, address indexed newMultiSig);
    event AssetsForwarded(address indexed asset, uint256 amount, address multiSig);
    event AssetsRetrieved(address indexed asset, uint256 amount, address multiSig);

    function setUp() public {
        admin = makeAddr("admin");
        multisig = makeAddr("multisig");
        operator = makeAddr("operator");

        // Deploy asset
        asset = new ERC20Mock();

        // Deploy mock vault
        vault = new MockVault(address(asset));

        // Deploy and initialize strategy
        strategy = deployAndInitializeStrategy();
    }

    function deployAndInitializeStrategy() internal returns (MultisigStrategy) {
        MultisigStrategy impl = new MultisigStrategy();

        // Create proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            MultisigStrategy.initialize.selector,
            admin,
            address(vault),
            multisig,
            uint64(1000), // maxAccountingChangeThreshold (10%)
            uint64(86400), // accountingValidityPeriod (1 day)
            uint64(3600) // cooldownPeriod (1 hour)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        return MultisigStrategy(address(proxy));
    }

    function testConstructor() public view {
        assertEq(strategy.asset(), address(asset));
        assertTrue(strategy.hasRole(PeripheryRolesLib.STRATEGY_ADMIN, admin));
        assertEq(strategy.getVault(), address(vault));
        assertEq(uint8(strategy.strategyType()), uint8(StrategyType.ASYNC));
        assertEq(strategy.maxAllocation(), type(uint256).max);
    }

    function testInitializeRevertIfInvalidMultiSigAddress() public {
        MultisigStrategy impl = new MultisigStrategy();

        // Create proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            MultisigStrategy.initialize.selector,
            admin,
            address(vault),
            multisig,
            uint64(100001), // maxAccountingChangeThreshold (100% + 1%)
            uint64(86400), // accountingValidityPeriod (1 day)
            uint64(3600) // cooldownPeriod (1 hour)
        );
        vm.expectRevert(abi.encodeWithSelector(PositionAccountingLib.InvalidMaxAccountingChangeThreshold.selector));
        new ERC1967Proxy(address(impl), initData);
    }

    function testInitialization() public view {
        assertEq(strategy.getMultiSig(), multisig);
        assertTrue(strategy.hasRole(PeripheryRolesLib.OPERATOR_ROLE, admin));
        assertTrue(strategy.isOperator(admin));
        assertEq(strategy.getMaxAccountingChangeThreshold(), 1000);
        assertEq(strategy.getAccountingValidityPeriod(), 86400);
        assertEq(strategy.getCooldownPeriod(), 3600);
    }

    function testSetMultiSig() public {
        address newMultisig = makeAddr("newMultisig");

        vm.expectEmit(true, true, false, true);
        emit MultiSigSet(multisig, newMultisig);

        vm.prank(admin);
        strategy.setMultiSig(newMultisig);

        assertEq(strategy.getMultiSig(), newMultisig);
    }

    function testSetOperator() public {
        address newOperator = makeAddr("newOperator");

        // Debug: Check if admin has admin role
        assertTrue(strategy.hasRole(PeripheryRolesLib.STRATEGY_ADMIN, admin), "Admin should have admin role");

        // Admin can grant operator role using AccessControl
        vm.startPrank(admin);
        strategy.grantRole(PeripheryRolesLib.OPERATOR_ROLE, newOperator);
        vm.stopPrank();

        assertTrue(strategy.isOperator(newOperator));

        // Test that the new operator can perform operator functions
        vm.prank(newOperator);
        strategy.adjustTotalAssets(1000, 1); // This should work
    }

    function testPauseUnpause() public {
        vm.prank(admin);
        strategy.pause();

        // Should be paused
        assertTrue(strategy.paused());

        vm.prank(admin);
        strategy.unpause();

        // Should be unpaused
        assertFalse(strategy.paused());
    }

    function testSetMaxAccountingChangeThreshold() public {
        uint64 newThreshold = 2000; // 20%

        vm.prank(admin);
        strategy.setMaxAccountingChangeThreshold(newThreshold);

        assertEq(strategy.getMaxAccountingChangeThreshold(), newThreshold);
    }

    function testSetMaxAccountingChangeThresholdInvalid() public {
        uint64 newThreshold = 10001; // 100% + 1%

        vm.prank(admin);
        vm.expectRevert(PositionAccountingLib.InvalidMaxAccountingChangeThreshold.selector);
        strategy.setMaxAccountingChangeThreshold(newThreshold);
    }

    function testSetAccountingValidityPeriod() public {
        uint64 newPeriod = 172800; // 2 days

        vm.prank(admin);
        strategy.setAccountingValidityPeriod(newPeriod);

        assertEq(strategy.getAccountingValidityPeriod(), newPeriod);
    }

    function testSetCooldownPeriod() public {
        uint64 newPeriod = 7200; // 2 hours

        vm.prank(admin);
        strategy.setCooldownPeriod(newPeriod);

        assertEq(strategy.getCooldownPeriod(), newPeriod);
    }

    function testUnauthorizedAccess() public {
        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert();
        strategy.setMultiSig(makeAddr("newMultisig"));

        vm.startPrank(unauthorized);
        bytes32 operatorRole = PeripheryRolesLib.OPERATOR_ROLE;
        vm.expectRevert();

        strategy.grantRole(operatorRole, makeAddr("newOperator"));
        vm.stopPrank();

        vm.prank(unauthorized);
        vm.expectRevert();
        strategy.setMaxWithdraw(0); // Disable withdrawals

        vm.prank(unauthorized);
        vm.expectRevert();
        strategy.pause();
    }

    function testInvalidParameters() public {
        // Test invalid multisig address
        vm.prank(admin);
        vm.expectRevert(MultisigStrategy.InvalidMultiSigAddress.selector);
        strategy.setMultiSig(address(0));

        // Test invalid accounting validity period
        vm.prank(admin);
        vm.expectRevert(PositionAccountingLib.InvalidAccountingValidityPeriod.selector);
        strategy.setAccountingValidityPeriod(1800); // Less than cooldown period

        // Test invalid update cooldown period
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(PositionAccountingLib.InvalidCooldownPeriod.selector)); // InvalidCooldownPeriod error selector
        strategy.setCooldownPeriod(86400); // Equal to validity period
    }

    function testMinimumPeriodDifferenceValidation() public {
        // Test 1: Try to set accounting validity period to exactly cooldown period + 60 (should succeed)
        vm.prank(admin);
        strategy.setAccountingValidityPeriod(3660); // 3600 + 60 = 3660 seconds

        // Test 2: Try to set accounting validity period to cooldown period + 59 (should fail)
        vm.prank(admin);
        vm.expectRevert(PositionAccountingLib.InvalidAccountingValidityPeriod.selector);
        strategy.setAccountingValidityPeriod(3659); // 3600 + 59 = 3659 seconds (1 second too little)

        // Test 3: Try to set accounting validity period to cooldown period + 61 (should succeed)
        vm.prank(admin);
        strategy.setAccountingValidityPeriod(3661); // 3600 + 61 = 3661 seconds

        // Test 4: Try to set cooldown period to exactly accounting validity period - 60 (should succeed)
        vm.prank(admin);
        strategy.setCooldownPeriod(3601); // 3661 - 60 = 3601 seconds

        // Test 5: Try to set cooldown period to accounting validity period - 59 (should fail)
        vm.prank(admin);
        vm.expectRevert(PositionAccountingLib.InvalidCooldownPeriod.selector);
        strategy.setCooldownPeriod(3602); // 3661 - 59 = 3602 seconds (1 second too much)

        // Test 6: Try to set cooldown period to accounting validity period - 61 (should succeed)
        vm.prank(admin);
        strategy.setCooldownPeriod(3600); // 3661 - 61 = 3600 seconds

        // Verify the final values
        assertEq(strategy.getCooldownPeriod(), 3600);
        assertEq(strategy.getAccountingValidityPeriod(), 3661);
    }

    function testAccountingNonce() public view {
        assertEq(strategy.getNextAccountingNonce(), 1);
    }

    function testDeallocateWhenWithdrawDisabled() public {
        uint256 amount = 1000e18;

        // First, allocate some funds to the strategy
        asset.mint(address(vault), amount);
        vm.prank(address(vault));
        asset.approve(address(strategy), amount);

        // Allocate funds
        bytes memory allocateData = abi.encode(amount);
        vm.prank(address(vault));
        strategy.allocateFunds(allocateData);

        // Disable withdrawals
        vm.prank(admin);
        strategy.setMaxWithdraw(0); // Disable withdrawals

        // Approve strategy to pull funds from multisig
        vm.prank(multisig);
        asset.approve(address(strategy), amount);

        // Try to deallocate funds - should work (deallocate is not restricted by maxWithdraw)
        bytes memory deallocateData = abi.encode(amount);
        vm.prank(address(vault));
        strategy.deallocateFunds(deallocateData);
    }

    function testWithdrawWhenWithdrawDisabled() public {
        uint256 amount = 1000e18;

        // First, allocate some funds to the strategy
        asset.mint(address(vault), amount);
        vm.prank(address(vault));
        asset.approve(address(strategy), amount);

        // Allocate funds
        bytes memory allocateData = abi.encode(amount);
        vm.prank(address(vault));
        strategy.allocateFunds(allocateData);

        // Disable withdrawals
        vm.prank(admin);
        strategy.setMaxWithdraw(0); // Disable withdrawals

        // Try to withdraw funds - should fail
        vm.prank(address(vault));
        vm.expectRevert(); // Should revert due to maxWithdraw being 0
        strategy.onWithdraw(amount);
    }

    function testDeallocateWhenWithdrawEnabled() public {
        uint256 amount = 1000e18;

        // First, allocate some funds to the strategy
        asset.mint(address(vault), amount);
        vm.prank(address(vault));
        asset.approve(address(strategy), amount);

        // Allocate funds
        bytes memory allocateData = abi.encode(amount);
        vm.prank(address(vault));
        strategy.allocateFunds(allocateData);

        // Mock the multisig to have the funds and approve the strategy
        asset.mint(multisig, amount);
        vm.prank(multisig);
        asset.approve(address(strategy), amount);

        // Deallocate funds - should succeed
        bytes memory deallocateData = abi.encode(amount);
        vm.prank(address(vault));
        uint256 deallocated = strategy.deallocateFunds(deallocateData);

        assertEq(deallocated, amount);

        // Verify assets were transferred to vault
        assertEq(asset.balanceOf(address(vault)), amount);
    }

    function testWithdrawWhenWithdrawEnabled() public {
        uint256 amount = 1000e18;

        // First, allocate some funds to the strategy
        asset.mint(address(vault), amount);
        vm.prank(address(vault));
        asset.approve(address(strategy), amount);

        // Allocate funds
        bytes memory allocateData = abi.encode(amount);
        vm.prank(address(vault));
        strategy.allocateFunds(allocateData);

        // Mock the multisig to have the funds and approve the strategy
        asset.mint(multisig, amount);
        vm.prank(multisig);
        asset.approve(address(strategy), amount);

        // Withdraw funds - should succeed
        vm.prank(address(vault));
        uint256 withdrawn = strategy.onWithdraw(amount);

        assertEq(withdrawn, amount);

        // Verify assets were transferred to vault
        assertEq(asset.balanceOf(address(vault)), amount);
    }
}
