// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IAdministeredAgent } from "../../src/interfaces/IAdministeredAgent.sol";

import { AdministeredAgent } from "../../src/AdministeredAgent.sol";

contract MockTarget {

    uint256 internal _counter = 1;

    function foo(uint256 bar) external payable returns (uint256 baz) {
        return bar * ++_counter;
    }

    receive() external payable {}

}

contract AdministeredAgent_IntegrationTests is Test {

    AdministeredAgent internal administeredAgent;

    address internal admin = makeAddr("admin");
    address internal actor = makeAddr("actor");

    function setUp() external {
        administeredAgent = new AdministeredAgent(admin);

        vm.prank(admin);
        administeredAgent.addActor(actor);
    }

    /**********************************************************************************************/
    /*** call Tests                                                                             ***/
    /**********************************************************************************************/

    function test_call_withValue() external {
        address target = address(new MockTarget());

        vm.deal(actor, 1 ether);

        assertEq(actor.balance,                      1 ether);
        assertEq(address(administeredAgent).balance, 0);
        assertEq(target.balance,                     0);

        vm.prank(actor);
        bytes memory result = administeredAgent.call{ value: 0.5 ether }(target, abi.encodeWithSelector(MockTarget.foo.selector, 1));

        assertEq(result, abi.encode(2));

        assertEq(actor.balance,                      0.5 ether);
        assertEq(address(administeredAgent).balance, 0);
        assertEq(target.balance,                     0.5 ether);
    }

    /**********************************************************************************************/
    /*** batchCall Tests                                                                        ***/
    /**********************************************************************************************/

    function test_batchCall_withValue() external {
        address target1 = address(new MockTarget());
        address target2 = address(new MockTarget());

        address[] memory targets = new address[](3);
        targets[0] = target1;
        targets[1] = target2;
        targets[2] = target2;

        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeWithSelector(MockTarget.foo.selector, 1);
        data[1] = abi.encodeWithSelector(MockTarget.foo.selector, 2);
        data[2] = abi.encodeWithSelector(MockTarget.foo.selector, 3);

        uint256[] memory values = new uint256[](3);
        values[0] = 0.2 ether;
        values[1] = 0;
        values[2] = 0.5 ether;

        vm.deal(actor, 1 ether);

        assertEq(actor.balance,                      1 ether);
        assertEq(address(administeredAgent).balance, 0);
        assertEq(target1.balance,                    0);
        assertEq(target2.balance,                    0);

        vm.prank(actor);
        bytes[] memory results = administeredAgent.batchCall{ value: 0.9 ether }(targets, data, values);

        assertEq(results.length, 3);

        assertEq(results[0], abi.encode(2));
        assertEq(results[1], abi.encode(4));
        assertEq(results[2], abi.encode(9));

        assertEq(actor.balance,                      0.1 ether);
        assertEq(address(administeredAgent).balance, 0.2 ether);
        assertEq(target1.balance,                    0.2 ether);
        assertEq(target2.balance,                    0.5 ether);
    }

    /**********************************************************************************************/
    /*** sendValue Tests                                                                        ***/
    /**********************************************************************************************/

    function test_sendValue() external {
        address target = address(new MockTarget());

        vm.deal(address(administeredAgent), 1 ether);

        assertEq(address(administeredAgent).balance, 1 ether);
        assertEq(target.balance,                     0);

        vm.prank(actor);
        administeredAgent.sendValue(target, 0.4 ether);

        assertEq(address(administeredAgent).balance, 0.6 ether);
        assertEq(target.balance,                     0.4 ether);
    }

}
