// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../contracts/GSTimelockController.sol";

contract GSTimelockControllerTest is Test {

    TestOwnableContract testContract;
    GSTimelockController timelock;
    address owner;
    address user1;
    address user2;
    uint256 minDelay;
    address[] proposers;
    address[] executors;
    address admin;

    function setUp() public {
        owner = vm.addr(12345);
        user1 = vm.addr(1);
        user2 = vm.addr(2);
        minDelay = 1000;
        proposers = new address[](1);
        executors = new address[](1);
        admin = vm.addr(3);

        proposers[0] = user1;
        executors[0] = user2;
        timelock = new GSTimelockController(minDelay, proposers, executors, admin);

        testContract = new TestOwnableContract();

        testContract.transferOwnership(address(timelock));

        bytes memory _data = abi.encodeCall(Ownable2Step.acceptOwnership, ());

        vm.prank(user1);
        timelock.schedule(address(testContract), 0, _data, "", "", 1000);

        vm.warp(1001);

        vm.prank(user2);
        timelock.execute(address(testContract), 0, _data, "", "");
    }

    function testTransferOwnership() public {

        assertEq(testContract.owner(), address(timelock));

        vm.startPrank(user1);

        bytes memory _data = abi.encodeCall(Ownable.transferOwnership, (owner));

        timelock.schedule(address(testContract), 0, _data, "", "", 1000);

        vm.stopPrank();

        vm.warp(2001);

        vm.startPrank(user2);

        assertEq(testContract.pendingOwner(), address(0));

        timelock.execute(address(testContract), 0, _data, "", "");

        vm.stopPrank();

        assertEq(testContract.pendingOwner(), owner);
        assertEq(testContract.owner(), address(timelock));

        vm.prank(owner);
        testContract.acceptOwnership();

        assertEq(testContract.owner(), owner);
    }

    function testEmergencyFunction() public {
        assertEq(testContract.owner(), address(timelock));
        assertFalse(testContract.isEmergencyCalled());

        vm.expectRevert("Ownable: caller is not the owner");
        testContract.emergencyFunction();

        vm.startPrank(address(timelock));

        testContract.emergencyFunction();
        assertTrue(testContract.isEmergencyCalled());

        vm.stopPrank();

        testContract.resetEmergencyFunction();
        assertFalse(testContract.isEmergencyCalled());
    }

    function testEmergencyFunctionErrorCalls() public {
        vm.startPrank(owner);

        vm.expectRevert("Ownable: caller is not the owner");
        testContract.emergencyFunction();

        vm.expectRevert("AccessControl: account 0xeb4665750b1382df4aebf49e04b429aaac4d9929 is missing role 0xbf233dd2aafeb4d50879c4aa5c81e96d92f6e6945c906a58f9f2d1c1631b4b26");
        timelock.executeEmergency(address(testContract), 0, "emergencyFunction()", new bytes(0));

        vm.stopPrank();

        vm.startPrank(admin);

        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EmergencyCallNotExists(bytes32)")),0xb4cbc6ecb7c21a97d07ddad29ddbcd88c38c1e0347cbf031e56a2a5636d023a4));
        timelock.executeEmergency(address(testContract), 0, "emergencyFunction()", new bytes(0));

        vm.expectRevert("TimelockController: caller must be timelock");
        timelock.addEmergencyCall(address(testContract), "emergencyFunction()");

        bytes memory _data = abi.encodeCall(GSTimelockController.addEmergencyCall, (address(testContract), "emergencyFunction()"));

        vm.expectRevert("AccessControl: account 0x6813eb9362372eef6200f3b1dbc3f819671cba69 is missing role 0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1");
        timelock.schedule(address(timelock), 0, _data, "", "", 0);

        vm.stopPrank();
    }

    function testAddRemoveEmergencyCall() public {
        bytes memory _data = abi.encodeCall(GSTimelockController.addEmergencyCall, (address(testContract), "emergencyFunction()"));
        vm.startPrank(user1);

        vm.expectRevert("TimelockController: insufficient delay");
        timelock.schedule(address(timelock), 0, _data, "", "", 0);

        bytes32 txId = timelock.hashOperation(address(timelock), 0, _data, "", "");

        timelock.schedule(address(timelock), 0, _data, "", "", 1000);

        vm.expectRevert("AccessControl: account 0x7e5f4552091a69125d5dfcb7b8c2659029395bdf is missing role 0xd8aa0f3194971a2a116679f7c2090f6939c8d4e01a2a8d7e41d55e5351469e63");
        timelock.execute(address(timelock), 0, _data, "", "");

        vm.stopPrank();

        vm.startPrank(user2);

        vm.expectRevert("TimelockController: operation is not ready");
        timelock.execute(address(timelock), 0, _data, "", "");

        assertFalse(timelock.hasEmergencyFunction(address(testContract), "emergencyFunction()"));

        vm.warp(2001);

        timelock.execute(address(timelock), 0, _data, "", "");

        assertTrue(timelock.hasEmergencyFunction(address(testContract), "emergencyFunction()"));

        vm.expectRevert("AccessControl: account 0x2b5ad5c4795c026514f8317c7a215e218dccd6cf is missing role 0xbf233dd2aafeb4d50879c4aa5c81e96d92f6e6945c906a58f9f2d1c1631b4b26");
        timelock.executeEmergency(address(testContract), 0, "emergencyFunction()", "");
        vm.stopPrank();

        vm.startPrank(admin);

        assertFalse(testContract.isEmergencyCalled());

        timelock.executeEmergency(address(testContract), 0, "emergencyFunction()", "");

        assertTrue(testContract.isEmergencyCalled());

        testContract.resetEmergencyFunction();

        assertFalse(testContract.isEmergencyCalled());

        timelock.executeEmergency(address(testContract), 0, "emergencyFunction()", "");

        assertTrue(testContract.isEmergencyCalled());

        testContract.resetEmergencyFunction();

        vm.expectRevert("TimelockController: caller must be timelock");
        timelock.removeEmergencyCall(address(testContract), "emergencyFunction()");

        timelock.grantRole(timelock.EMERGENCY_ROLE(), user2);

        vm.stopPrank();

        vm.startPrank(user2);

        assertFalse(testContract.isEmergencyCalled());

        timelock.executeEmergency(address(testContract), 0, "emergencyFunction()", "");

        assertTrue(testContract.isEmergencyCalled());

        testContract.resetEmergencyFunction();

        assertFalse(testContract.isEmergencyCalled());

        timelock.renounceRole(timelock.EMERGENCY_ROLE(), user2);

        vm.expectRevert("AccessControl: account 0x2b5ad5c4795c026514f8317c7a215e218dccd6cf is missing role 0xbf233dd2aafeb4d50879c4aa5c81e96d92f6e6945c906a58f9f2d1c1631b4b26");
        timelock.executeEmergency(address(testContract), 0, "emergencyFunction()", "");

        assertFalse(testContract.isEmergencyCalled());

        vm.stopPrank();

        vm.startPrank(user1);
        _data = abi.encodeCall(GSTimelockController.removeEmergencyCall, (address(testContract), "emergencyFunction()"));

        timelock.schedule(address(timelock), 0, _data, txId, "", 1000);

        vm.stopPrank();

        vm.startPrank(user2);

        vm.warp(3001);

        assertTrue(timelock.hasEmergencyFunction(address(testContract), "emergencyFunction()"));

        timelock.execute(address(timelock), 0, _data, txId, "");

        assertFalse(timelock.hasEmergencyFunction(address(testContract), "emergencyFunction()"));

        vm.stopPrank();

        vm.startPrank(user1);

        txId = timelock.hashOperation(address(timelock), 0, _data, txId, "");

        timelock.schedule(address(timelock), 0, _data, txId, "", 1000);

        vm.stopPrank();

        vm.startPrank(user2);

        vm.warp(4001);

        vm.expectRevert("TimelockController: underlying transaction reverted");
        timelock.execute(address(timelock), 0, _data, txId, "");

        txId = timelock.hashOperation(address(timelock), 0, _data, txId, "");

        vm.stopPrank();

        vm.startPrank(user1);

        timelock.cancel(txId);

        vm.stopPrank();

        vm.startPrank(admin);
        assertFalse(testContract.isEmergencyCalled());

        assertFalse(timelock.hasEmergencyFunction(address(testContract), "emergencyFunction()"));

        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EmergencyCallNotExists(bytes32)")),0xb4cbc6ecb7c21a97d07ddad29ddbcd88c38c1e0347cbf031e56a2a5636d023a4));
        timelock.executeEmergency(address(testContract), 0, "emergencyFunction()", "");

        assertFalse(testContract.isEmergencyCalled());

        assertFalse(timelock.hasEmergencyFunction(address(testContract), "emergencyFunction()"));

        vm.stopPrank();
    }
}

contract TestOwnableContract is Ownable2Step {

    bool public isEmergencyCalled;

    constructor() Ownable() {
        isEmergencyCalled = false;
    }

    function resetEmergencyFunction() public {
        isEmergencyCalled = false;
    }

    function emergencyFunction() public onlyOwner {
        isEmergencyCalled = true;
    }
}