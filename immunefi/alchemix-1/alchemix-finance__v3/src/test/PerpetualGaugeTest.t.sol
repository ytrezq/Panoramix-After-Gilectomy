// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {PerpetualGauge} from "../PerpetualGauge.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
// --- Mock contracts ---

contract MockERC20 is IERC20Metadata {
    string public name = "Mock Token";
    string public symbol = "MCK";
    uint8 public decimals = 18;
    uint256 public totalSupply = 1e24; // 1 million tokens (1e6 * 1e18)

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor() {
        balanceOf[msg.sender] = totalSupply;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient");
        require(allowance[from][msg.sender] >= amount, "Not allowed");
        balanceOf[from] -= amount;
        allowance[from][msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockStrategyClassifier {
    mapping(uint256 => uint8) public risk;
    mapping(uint256 => uint256) public indivCap;
    mapping(uint8 => uint256) public globalCap;

    function setRisk(uint256 stratId, uint8 _risk) external {
        risk[stratId] = _risk;
    }

    function setIndivCap(uint256 stratId, uint256 cap) external {
        indivCap[stratId] = cap;
    }

    function setGlobalCap(uint8 riskLevel, uint256 cap) external {
        globalCap[riskLevel] = cap;
    }

    function getStrategyRiskLevel(uint256 stratId) external view returns (uint8) {
        return risk[stratId];
    }

    function getIndividualCap(uint256 stratId) external view returns (uint256) {
        return indivCap[stratId];
    }

    function getGlobalCap(uint8 riskLevel) external view returns (uint256) {
        return globalCap[riskLevel];
    }
}

contract MockAllocatorProxy {
    event Allocated(uint256 strategyId, uint256 amount);

    function allocate(uint256 strategyId, uint256 amount) external {
        emit Allocated(strategyId, amount);
    }
}

/* contract MockERC20Test is Test {
    MockERC20 public mockERC20;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address charlie = address(0x0C0);

    function setUp() public {
        mockERC20 = new MockERC20();
        mockERC20.transfer(alice, 1000e18);
        mockERC20.transfer(bob, 500e18);
    }

    function testMockERC20TransferFunctionSignature() public {
        // Test that the transfer function has the correct selector
        bytes4 expectedSelector = bytes4(keccak256("transfer(address,uint256)"));
        bytes4 actualSelector = mockERC20.transfer.selector;
        assertEq(actualSelector, expectedSelector);
    }

    function testMockERC20ApproveFunctionSignature() public {
        // Test that the approve function has the correct selector
        bytes4 expectedSelector = bytes4(keccak256("approve(address,uint256)"));
        bytes4 actualSelector = mockERC20.approve.selector;
        assertEq(actualSelector, expectedSelector);
    }

    function testMockERC20TransferFromFunctionSignature() public {
        // Test that the transferFrom function has the correct selector
        bytes4 expectedSelector = bytes4(keccak256("transferFrom(address,address,uint256)"));
        bytes4 actualSelector = mockERC20.transferFrom.selector;
        assertEq(actualSelector, expectedSelector);
    }

    function testMockERC20IERC20Compliance() public {
        // Test that MockERC20 implements IERC20Metadata interface
        IERC20Metadata ierc20 = IERC20Metadata(address(mockERC20));
        // Test basic token properties
        assertEq(ierc20.name(), "Mock Token");
        assertEq(ierc20.symbol(), "MCK");
        assertEq(ierc20.decimals(), 18);

        // Test interface functions
        assertEq(ierc20.totalSupply(), 1e24);
        assertEq(ierc20.balanceOf(alice), 1000e18);
        assertEq(ierc20.allowance(alice, bob), 0);

        vm.startPrank(alice);
        assertTrue(ierc20.approve(bob, 100e18));
        assertTrue(ierc20.transfer(charlie, 10e18));
        assertTrue(ierc20.transferFrom(alice, bob, 10e18));
        vm.stopPrank();
    }
}
 */
// --- Test Suite ---

contract PerpetualGaugeTest is Test {
    PerpetualGauge gauge;
    MockERC20 token;
    MockStrategyClassifier classifier;
    MockAllocatorProxy allocator;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        token = new MockERC20();
        classifier = new MockStrategyClassifier();
        allocator = new MockAllocatorProxy();

        gauge = new PerpetualGauge(address(classifier), address(allocator), address(token));

        // Give tokens to Alice and Bob
        token.transfer(alice, 1e21);
        token.transfer(bob, 1e21);

        // Setup classifier caps
        classifier.setIndivCap(1, 5000); // 50% cap
        classifier.setGlobalCap(1, 8000); // 80% for risk group 1
        classifier.setRisk(1, 1);
    }

    // --- Voting Tests ---
    /* 
    function testVoteIncreasesWeights() public {
        vm.prank(alice);
        gauge.vote(1, _arr(1), _arr(100));

        (uint256[] memory sIds, uint256[] memory weights) = gauge.getCurrentAllocations(1);
        assertEq(sIds.length, 0, "strategyList not populated yet");
        // because registerNewStrategy not complete TODO in contract
    }

    function testVoteThenClear() public {
        vm.startPrank(alice);
        gauge.vote(1, _arr(1), _arr(100));
        gauge.clearVote(1);
        vm.stopPrank();
    }

    function testVoteExpiryLogic() public {
        vm.prank(alice);
        gauge.vote(1, _arr(1), _arr(100));

        // Warp past expiry
        vm.warp(block.timestamp + 366 days);
        // Should reset expiry
        vm.prank(alice);
        gauge.vote(1, _arr(1), _arr(200));
    }
    */
    // --- Allocation Tests ---
    /*     function testExecuteAllocationAppliesCaps() public {
        // Add strategy slot
        // FIXME gauge.strategyList(1).push(1); // direct storage modification in test (unsafe in prod)

        vm.prank(alice);
        gauge.vote(1, _arr(1), _arr(100));

        // Force aggregator to contain weight
        uint256 idle = 1e18;

        vm.expectEmit(true, true, true, true);
        emit MockAllocatorProxy.Allocated(1, idle / 2); // since indivCap is 50%

        gauge.executeAllocation(1, idle);
    } */

    /*     function testMultipleVotersAggregate() public {
        // Add strategy slot
        // FIXME gauge.strategyList(1).push(1);

        vm.prank(alice);
        gauge.vote(1, _arr(1), _arr(100));

        vm.prank(bob);
        gauge.vote(1, _arr(1), _arr(100));

        (uint256[] memory sIds, uint256[] memory weights) = gauge.getCurrentAllocations(1);

        assertEq(sIds.length, 1);
        assertEq(weights[0], 1e18, "Full allocation weight");
    } */

    // Helper function for arrays
    function _arr(uint256 v) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](1);
        arr[0] = v;
        return arr;
    }
}
