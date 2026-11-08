// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AlchemistStrategyClassifier} from "../AlchemistStrategyClassifier.sol";

contract MockStrategyClassifier is AlchemistStrategyClassifier {
    constructor(address _admin) AlchemistStrategyClassifier(_admin) {}
}

contract AlchemistStrategyClassifierTest is Test {
    MockStrategyClassifier public classifier;

    address public admin = address(0x1111111111111111111111111111111111111111);
    address public newAdmin = address(0x2222222222222222222222222222222222222222);
    address public unauthorized = address(0x3333333333333333333333333333333333333333);

    uint256 public constant STRATEGY_ID_1 = 1;
    uint256 public constant STRATEGY_ID_2 = 2;
    uint8 public constant RISK_LEVEL_LOW = 0;
    uint8 public constant RISK_LEVEL_MEDIUM = 1;
    uint8 public constant RISK_LEVEL_HIGH = 2;

    event AdminChanged(address indexed admin);
    event RiskClassModified(uint256 indexed class, uint256 indexed globalCap, uint256 indexed localCap);

    function setUp() public {
        vm.startPrank(admin);
        classifier = new MockStrategyClassifier(admin);
        vm.stopPrank();
    }

    // ===== setRiskClass Tests =====

    function testSetRiskClass() public {
        vm.startPrank(admin);
        uint256 globalCap = 1000e18;
        uint256 localCap = 100e18;

        vm.expectEmit(true, true, true, true);
        emit RiskClassModified(RISK_LEVEL_LOW, globalCap, localCap);

        classifier.setRiskClass(RISK_LEVEL_LOW, globalCap, localCap);
        vm.stopPrank();
        assertEq(classifier.getGlobalCap(RISK_LEVEL_LOW), globalCap);
        (uint256 storedGlobalCap, uint256 storedLocalCap) = classifier.riskClasses(RISK_LEVEL_LOW);
        assertEq(storedGlobalCap, globalCap);
        assertEq(storedLocalCap, localCap);
    }

    function testSetRiskClassMultipleClasses() public {
        uint256 lowGlobalCap = 1000e18;
        uint256 lowLocalCap = 100e18;
        uint256 highGlobalCap = 500e18;
        uint256 highLocalCap = 50e18;

        vm.startPrank(admin);
        classifier.setRiskClass(RISK_LEVEL_LOW, lowGlobalCap, lowLocalCap);
        classifier.setRiskClass(RISK_LEVEL_HIGH, highGlobalCap, highLocalCap);
        vm.stopPrank();
        assertEq(classifier.getGlobalCap(RISK_LEVEL_LOW), lowGlobalCap);
        assertEq(classifier.getGlobalCap(RISK_LEVEL_HIGH), highGlobalCap);
    }

    // ===== assignStrategyRiskLevel Tests =====

    function testAssignStrategyRiskLevel() public {
        vm.startPrank(admin);
        classifier.assignStrategyRiskLevel(STRATEGY_ID_1, RISK_LEVEL_MEDIUM);
        vm.stopPrank();

        assertEq(classifier.getStrategyRiskLevel(STRATEGY_ID_1), RISK_LEVEL_MEDIUM);
        assertEq(classifier.strategyRiskLevel(STRATEGY_ID_1), RISK_LEVEL_MEDIUM);
    }

    function testAssignStrategyRiskLevelMultipleStrategies() public {
        vm.startPrank(admin);
        classifier.assignStrategyRiskLevel(STRATEGY_ID_1, RISK_LEVEL_LOW);
        classifier.assignStrategyRiskLevel(STRATEGY_ID_2, RISK_LEVEL_HIGH);
        vm.stopPrank();

        assertEq(classifier.getStrategyRiskLevel(STRATEGY_ID_1), RISK_LEVEL_LOW);
        assertEq(classifier.getStrategyRiskLevel(STRATEGY_ID_2), RISK_LEVEL_HIGH);
    }

    function testAssignStrategyRiskLevelUnauthorizedRevert() public {
        vm.startPrank(unauthorized);
        vm.expectRevert(abi.encode("PD"));
        classifier.assignStrategyRiskLevel(STRATEGY_ID_1, RISK_LEVEL_MEDIUM);
        vm.stopPrank();
    }

    // ===== transferOwnership Tests =====

    function testTransferOwnership() public {
        vm.startPrank(admin);
        classifier.transferOwnership(newAdmin);
        vm.stopPrank();

        assertEq(classifier.pendingAdmin(), newAdmin);
        assertEq(classifier.admin(), admin); // Should still be old admin until accepted
    }

    function testTransferOwnershipUnauthorizedRevert() public {
        vm.startPrank(unauthorized);
        vm.expectRevert(abi.encode("PD"));
        classifier.transferOwnership(newAdmin);
        vm.stopPrank();
    }

    // ===== acceptOwnership Tests =====

    function testAcceptOwnership() public {
        // First transfer ownership
        vm.startPrank(admin);
        classifier.transferOwnership(newAdmin);
        vm.stopPrank();

        // Then accept it
        vm.startPrank(newAdmin);
        vm.expectEmit(true, false, false, false);
        emit AdminChanged(newAdmin);

        classifier.acceptOwnership();
        vm.stopPrank();

        assertEq(classifier.admin(), newAdmin);
        assertEq(classifier.pendingAdmin(), address(0));
    }

    function testAcceptOwnershipUnauthorizedRevert() public {
        // Transfer ownership to newAdmin
        vm.startPrank(admin);
        classifier.transferOwnership(newAdmin);
        vm.stopPrank();

        // Try to accept with unauthorized address
        vm.startPrank(unauthorized);
        vm.expectRevert(abi.encode("PD"));
        classifier.acceptOwnership();
        vm.stopPrank();
    }

    function testAcceptOwnershipNoPendingAdminRevert() public {
        // Try to accept ownership when no transfer was initiated
        vm.startPrank(newAdmin);
        vm.expectRevert(abi.encode("PD"));
        classifier.acceptOwnership();
        vm.stopPrank();
    }
}
