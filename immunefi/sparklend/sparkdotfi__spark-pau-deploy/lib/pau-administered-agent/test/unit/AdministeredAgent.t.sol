// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { EnumerableSet } from "../../lib/openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IAdministeredAgent } from "../../src/interfaces/IAdministeredAgent.sol";

import { AdministeredAgent } from "../../src/AdministeredAgent.sol";

contract AdministeredAgentHarness is AdministeredAgent {

    using EnumerableSet for EnumerableSet.AddressSet;

    constructor(address admin_) AdministeredAgent(admin_) {}

    function __addAdmin(address account) external {
        _addAdmin(account);
    }

    function __removeAdmin(address account) external {
        _admins.remove(account);
    }

    function __addActor(address account) external {
        _actors.add(account);
    }

    function __removeActor(address account) external {
        _actors.remove(account);
    }

    function __addGrantor(address account) external {
        _grantors.add(account);
    }

    function __removeGrantor(address account) external {
        _grantors.remove(account);
    }

    function __addRevoker(address account) external {
        _revokers.add(account);
    }

    function __removeRevoker(address account) external {
        _revokers.remove(account);
    }

    function __getAdmin(uint256 index) external view returns (address) {
        return _admins.at(index);
    }

    function __getActor(uint256 index) external view returns (address) {
        return _actors.at(index);
    }

    function __getGrantor(uint256 index) external view returns (address) {
        return _grantors.at(index);
    }

    function __getRevoker(uint256 index) external view returns (address) {
        return _revokers.at(index);
    }

    function __isAdmin(address account) external view returns (bool) {
        return _admins.contains(account);
    }

    function __isActor(address account) external view returns (bool) {
        return _actors.contains(account);
    }

    function __isGrantor(address account) external view returns (bool) {
        return _grantors.contains(account);
    }

    function __isRevoker(address account) external view returns (bool) {
        return _revokers.contains(account);
    }

}

contract AdministeredAgent_UnitTests is Test {

    address internal actor        = makeAddr("actor");
    address internal admin        = makeAddr("admin");
    address internal deployer     = makeAddr("deployer");
    address internal grantor      = makeAddr("grantor");
    address internal otherAdmin   = makeAddr("otherAdmin");
    address internal revoker      = makeAddr("revoker");
    address internal unauthorized = makeAddr("unauthorized");

    AdministeredAgentHarness internal administeredAgent;

    function setUp() external {
        vm.prank(deployer);
        administeredAgent = new AdministeredAgentHarness(admin);
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroAccount() external {
        vm.expectRevert(IAdministeredAgent.ZeroAccount.selector);
        new AdministeredAgent(address(0));
    }

    function test_constructor() external {
        vm.expectEmit();
        emit IAdministeredAgent.AdminAdded(admin, deployer);

        vm.prank(deployer);
        AdministeredAgentHarness administeredAgent_ = new AdministeredAgentHarness(admin);

        assertEq(administeredAgent_.adminCount(),     1);
        assertEq(administeredAgent_.__isAdmin(admin), true);
        assertEq(administeredAgent_.__getAdmin(0),    admin);
    }

    /**********************************************************************************************/
    /*** addAdmin Tests                                                                         ***/
    /**********************************************************************************************/

    function test_addAdmin_notAdmin() external {
        vm.expectRevert(IAdministeredAgent.NotAdmin.selector);

        vm.prank(unauthorized);
        administeredAgent.addAdmin(otherAdmin);
    }

    function test_addAdmin_zeroAccount() external {
        vm.expectRevert(IAdministeredAgent.ZeroAccount.selector);

        vm.prank(admin);
        administeredAgent.addAdmin(address(0));
    }

    function test_addAdmin_accountAlreadyAdmin() external {
        vm.expectRevert(IAdministeredAgent.AccountAlreadyAdmin.selector);

        vm.prank(admin);
        administeredAgent.addAdmin(admin);
    }

    function test_addAdmin() external {
        assertEq(administeredAgent.adminCount(),          1);
        assertEq(administeredAgent.__isAdmin(otherAdmin), false);

        vm.expectEmit(address(administeredAgent));
        emit IAdministeredAgent.AdminAdded(otherAdmin, admin);

        vm.prank(admin);
        administeredAgent.addAdmin(otherAdmin);

        assertEq(administeredAgent.adminCount(),          2);
        assertEq(administeredAgent.__isAdmin(otherAdmin), true);
    }

    /**********************************************************************************************/
    /*** removeAdmin Tests                                                                      ***/
    /**********************************************************************************************/

    function test_removeAdmin_notAdmin() external {
        vm.expectRevert(IAdministeredAgent.NotAdmin.selector);

        vm.prank(unauthorized);
        administeredAgent.removeAdmin(admin);
    }

    function test_removeAdmin_accountNotAdmin() external {
        vm.expectRevert(IAdministeredAgent.AccountNotAdmin.selector);

        vm.prank(admin);
        administeredAgent.removeAdmin(unauthorized);
    }

    function test_removeAdmin_noAdminsRemaining() external {
        vm.expectRevert(IAdministeredAgent.NoAdminsRemaining.selector);

        vm.prank(admin);
        administeredAgent.removeAdmin(admin);
    }

    function test_removeAdmin() external {
        administeredAgent.__addAdmin(otherAdmin);

        assertEq(administeredAgent.adminCount(),          2);
        assertEq(administeredAgent.__isAdmin(otherAdmin), true);

        vm.expectEmit(address(administeredAgent));
        emit IAdministeredAgent.AdminRemoved(otherAdmin, admin);

        vm.prank(admin);
        administeredAgent.removeAdmin(otherAdmin);

        assertEq(administeredAgent.adminCount(),          1);
        assertEq(administeredAgent.__isAdmin(otherAdmin), false);
    }

    /**********************************************************************************************/
    /*** addGrantor Tests                                                                       ***/
    /**********************************************************************************************/

    function test_addGrantor_notAdmin() external {
        vm.expectRevert(IAdministeredAgent.NotAdmin.selector);

        vm.prank(unauthorized);
        administeredAgent.addGrantor(grantor);
    }

    function test_addGrantor_zeroAccount() external {
        vm.expectRevert(IAdministeredAgent.ZeroAccount.selector);

        vm.prank(admin);
        administeredAgent.addGrantor(address(0));
    }

    function test_addGrantor_accountAlreadyGrantor() external {
        administeredAgent.__addGrantor(grantor);

        vm.expectRevert(IAdministeredAgent.AccountAlreadyGrantor.selector);

        vm.prank(admin);
        administeredAgent.addGrantor(grantor);
    }

    function test_addGrantor() external {
        assertEq(administeredAgent.grantorCount(),       0);
        assertEq(administeredAgent.__isGrantor(grantor), false);

        vm.expectEmit(address(administeredAgent));
        emit IAdministeredAgent.GrantorAdded(grantor, admin);

        vm.prank(admin);
        administeredAgent.addGrantor(grantor);

        assertEq(administeredAgent.grantorCount(),       1);
        assertEq(administeredAgent.__isGrantor(grantor), true);
    }

    /**********************************************************************************************/
    /*** removeGrantor Tests                                                                    ***/
    /**********************************************************************************************/

    function test_removeGrantor_notAdmin() external {
        vm.expectRevert(IAdministeredAgent.NotAdmin.selector);

        vm.prank(unauthorized);
        administeredAgent.removeGrantor(grantor);
    }

    function test_removeGrantor_accountNotGrantor() external {
        vm.expectRevert(IAdministeredAgent.AccountNotGrantor.selector);

        vm.prank(admin);
        administeredAgent.removeGrantor(grantor);
    }

    function test_removeGrantor() external {
        administeredAgent.__addGrantor(grantor);

        assertEq(administeredAgent.grantorCount(),       1);
        assertEq(administeredAgent.__isGrantor(grantor), true);

        vm.expectEmit(address(administeredAgent));
        emit IAdministeredAgent.GrantorRemoved(grantor, admin);

        vm.prank(admin);
        administeredAgent.removeGrantor(grantor);

        assertEq(administeredAgent.grantorCount(),       0);
        assertEq(administeredAgent.__isGrantor(grantor), false);
    }

    /**********************************************************************************************/
    /*** addRevoker Tests                                                                       ***/
    /**********************************************************************************************/

    function test_addRevoker_notAdmin() external {
        vm.expectRevert(IAdministeredAgent.NotAdmin.selector);

        vm.prank(unauthorized);
        administeredAgent.addRevoker(revoker);
    }

    function test_addRevoker_zeroAccount() external {
        vm.expectRevert(IAdministeredAgent.ZeroAccount.selector);

        vm.prank(admin);
        administeredAgent.addRevoker(address(0));
    }

    function test_addRevoker_accountAlreadyRevoker() external {
        administeredAgent.__addRevoker(revoker);

        vm.expectRevert(IAdministeredAgent.AccountAlreadyRevoker.selector);

        vm.prank(admin);
        administeredAgent.addRevoker(revoker);
    }

    function test_addRevoker() external {
        assertEq(administeredAgent.revokerCount(),       0);
        assertEq(administeredAgent.__isRevoker(revoker), false);

        vm.expectEmit(address(administeredAgent));
        emit IAdministeredAgent.RevokerAdded(revoker, admin);

        vm.prank(admin);
        administeredAgent.addRevoker(revoker);

        assertEq(administeredAgent.revokerCount(),       1);
        assertEq(administeredAgent.__isRevoker(revoker), true);
    }

    /**********************************************************************************************/
    /*** removeRevoker Tests                                                                    ***/
    /**********************************************************************************************/

    function test_removeRevoker_notAdmin() external {
        vm.expectRevert(IAdministeredAgent.NotAdmin.selector);

        vm.prank(unauthorized);
        administeredAgent.removeRevoker(revoker);
    }

    function test_removeRevoker_accountNotRevoker() external {
        vm.expectRevert(IAdministeredAgent.AccountNotRevoker.selector);

        vm.prank(admin);
        administeredAgent.removeRevoker(revoker);
    }

    function test_removeRevoker() external {
        administeredAgent.__addRevoker(revoker);

        assertEq(administeredAgent.revokerCount(),       1);
        assertEq(administeredAgent.__isRevoker(revoker), true);

        vm.expectEmit(address(administeredAgent));
        emit IAdministeredAgent.RevokerRemoved(revoker, admin);

        vm.prank(admin);
        administeredAgent.removeRevoker(revoker);

        assertEq(administeredAgent.revokerCount(),       0);
        assertEq(administeredAgent.__isRevoker(revoker), false);
    }

    /**********************************************************************************************/
    /*** addActor Tests                                                                         ***/
    /**********************************************************************************************/

    function test_addActor_notGrantor() external {
        vm.expectRevert(IAdministeredAgent.NotGrantor.selector);

        vm.prank(unauthorized);
        administeredAgent.addActor(actor);
    }

    function test_addActor_zeroAccount() external {
        vm.expectRevert(IAdministeredAgent.ZeroAccount.selector);

        vm.prank(admin);
        administeredAgent.addActor(address(0));
    }

    function test_addActor_accountAlreadyActor() external {
        administeredAgent.__addActor(actor);

        vm.expectRevert(IAdministeredAgent.AccountAlreadyActor.selector);

        vm.prank(admin);
        administeredAgent.addActor(actor);
    }

    function test_addActor_asAdmin() external {
        assertEq(administeredAgent.actorCount(),     0);
        assertEq(administeredAgent.__isActor(actor), false);

        vm.expectEmit(address(administeredAgent));
        emit IAdministeredAgent.ActorAdded(actor, admin);

        vm.prank(admin);
        administeredAgent.addActor(actor);

        assertEq(administeredAgent.actorCount(),     1);
        assertEq(administeredAgent.__isActor(actor), true);
    }

    function test_addActor_asGrantor() external {
        administeredAgent.__addGrantor(grantor);

        assertEq(administeredAgent.actorCount(),     0);
        assertEq(administeredAgent.__isActor(actor), false);

        vm.expectEmit(address(administeredAgent));
        emit IAdministeredAgent.ActorAdded(actor, grantor);

        vm.prank(grantor);
        administeredAgent.addActor(actor);

        assertEq(administeredAgent.actorCount(),     1);
        assertEq(administeredAgent.__isActor(actor), true);
    }

    /**********************************************************************************************/
    /*** removeActor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_removeActor_notRevoker() external {
        vm.expectRevert(IAdministeredAgent.NotRevoker.selector);

        vm.prank(unauthorized);
        administeredAgent.removeActor(actor);
    }

    function test_removeActor_accountNotActor() external {
        vm.expectRevert(IAdministeredAgent.AccountNotActor.selector);

        vm.prank(admin);
        administeredAgent.removeActor(actor);
    }

    function test_removeActor_asAdmin() external {
        administeredAgent.__addActor(actor);

        assertEq(administeredAgent.actorCount(),     1);
        assertEq(administeredAgent.__isActor(actor), true);

        vm.expectEmit(address(administeredAgent));
        emit IAdministeredAgent.ActorRemoved(actor, admin);

        vm.prank(admin);
        administeredAgent.removeActor(actor);

        assertEq(administeredAgent.actorCount(),     0);
        assertEq(administeredAgent.__isActor(actor), false);
    }

    function test_removeActor_asRevoker() external {
        administeredAgent.__addActor(actor);
        administeredAgent.__addRevoker(revoker);

        assertEq(administeredAgent.actorCount(),     1);
        assertEq(administeredAgent.__isActor(actor), true);

        vm.expectEmit(address(administeredAgent));
        emit IAdministeredAgent.ActorRemoved(actor, revoker);

        vm.prank(revoker);
        administeredAgent.removeActor(actor);

        assertEq(administeredAgent.actorCount(),     0);
        assertEq(administeredAgent.__isActor(actor), false);
    }

    /**********************************************************************************************/
    /*** call Tests                                                                             ***/
    /**********************************************************************************************/

    function test_call_notActor() external {
        vm.expectRevert(IAdministeredAgent.NotActor.selector);

        vm.prank(unauthorized);
        administeredAgent.call(makeAddr("target"), hex"12345678");
    }

    function test_call_invalidTarget() external {
        administeredAgent.__addActor(actor);

        vm.expectRevert(IAdministeredAgent.InvalidTarget.selector);

        vm.prank(actor);
        administeredAgent.call(
            address(administeredAgent),
            abi.encodeCall(IAdministeredAgent.addAdmin, (actor))
        );
    }

    function test_call_reverts() external {
        administeredAgent.__addActor(actor);

        address target = makeAddr("target");

        bytes memory data = hex"12345678";

        vm.mockCallRevert(target, data, hex"87654321");

        vm.expectRevert(bytes(hex"87654321"));

        vm.prank(actor);
        administeredAgent.call(address(target), data);
    }

    function test_call_withNoValue() external {
        administeredAgent.__addActor(actor);

        address target = makeAddr("target");

        bytes memory data = hex"12345678";

        vm.mockCall(target,   data, hex"87654321");
        vm.expectCall(target, data);

        vm.prank(actor);
        bytes memory result = administeredAgent.call(address(target), data);

        assertEq(keccak256(result), keccak256(hex"87654321"));
    }

    function test_call_withValue() external {
        administeredAgent.__addActor(actor);

        address target = makeAddr("target");

        bytes memory data = hex"12345678";

        vm.deal(actor, 1 ether);

        vm.mockCall(target,   0.5 ether, data, hex"87654321");
        vm.expectCall(target, 0.5 ether, data);

        vm.prank(actor);
        bytes memory result = administeredAgent.call{ value: 0.5 ether }(address(target), data);

        assertEq(keccak256(result), keccak256(hex"87654321"));
    }

    /**********************************************************************************************/
    /*** batchCall Tests                                                                        ***/
    /**********************************************************************************************/

    function test_batchCall_notActor() external {
        vm.expectRevert(IAdministeredAgent.NotActor.selector);

        vm.prank(unauthorized);
        administeredAgent.batchCall(new address[](0), new bytes[](0), new uint256[](0));
    }

    function test_batchCall_mismatchedArrayLengths() external {
        administeredAgent.__addActor(actor);

        vm.expectRevert(IAdministeredAgent.MismatchedArrayLengths.selector);

        vm.prank(actor);
        administeredAgent.batchCall(new address[](2), new bytes[](1), new uint256[](1));

        vm.expectRevert(IAdministeredAgent.MismatchedArrayLengths.selector);

        vm.prank(actor);
        administeredAgent.batchCall(new address[](1), new bytes[](2), new uint256[](1));

        vm.expectRevert(IAdministeredAgent.MismatchedArrayLengths.selector);

        vm.prank(actor);
        administeredAgent.batchCall(new address[](1), new bytes[](1), new uint256[](2));
    }

    function test_batchCall_invalidTarget() external {
        administeredAgent.__addActor(actor);

        address[] memory targets = new address[](2);
        targets[0] = makeAddr("target1");
        targets[1] = address(administeredAgent);

        bytes[] memory data = new bytes[](2);
        data[0] = hex"12345678";
        data[1] = abi.encodeCall(IAdministeredAgent.addAdmin, (actor));

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        vm.mockCall(targets[0], data[0], "");

        vm.expectRevert(IAdministeredAgent.InvalidTarget.selector);

        vm.prank(actor);
        administeredAgent.batchCall(targets, data, values);
    }

    function test_batchCall_reverts() external {
        administeredAgent.__addActor(actor);

        address[] memory targets = new address[](3);
        targets[0] = makeAddr("target1");
        targets[1] = makeAddr("target2");
        targets[2] = makeAddr("target2");

        bytes[] memory data = new bytes[](3);
        data[0] = hex"12345678";
        data[1] = hex"87654321";
        data[2] = hex"11111111";

        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        vm.mockCallRevert(targets[0], data[0], hex"22222222");

        vm.expectRevert(bytes(hex"22222222"));

        vm.prank(actor);
        administeredAgent.batchCall(targets, data, values);

        vm.mockCall(targets[0],       data[0], "");
        vm.mockCallRevert(targets[1], data[1], hex"33333333");

        vm.expectRevert(bytes(hex"33333333"));

        vm.prank(actor);
        administeredAgent.batchCall(targets, data, values);

        vm.mockCall(targets[0],       data[0], "");
        vm.mockCall(targets[1],       data[1], "");
        vm.mockCallRevert(targets[2], data[2], hex"44444444");

        vm.expectRevert(bytes(hex"44444444"));

        vm.prank(actor);
        administeredAgent.batchCall(targets, data, values);
    }

    function test_batchCall_withNoValue() external {
        administeredAgent.__addActor(actor);

        address[] memory targets = new address[](3);
        targets[0] = makeAddr("target1");
        targets[1] = makeAddr("target2");
        targets[2] = makeAddr("target2");

        bytes[] memory data = new bytes[](3);
        data[0] = hex"12345678";
        data[1] = hex"87654321";
        data[2] = hex"11111111";

        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        vm.mockCall(targets[0],   data[0], hex"22222222");
        vm.expectCall(targets[0], data[0]);
        vm.mockCall(targets[1],   data[1], hex"33333333");
        vm.expectCall(targets[1], data[1]);
        vm.mockCall(targets[2],   data[2], hex"44444444");
        vm.expectCall(targets[2], data[2]);

        vm.prank(actor);
        bytes[] memory results = administeredAgent.batchCall(targets, data, values);

        assertEq(results.length, 3);

        assertEq(keccak256(results[0]), keccak256(hex"22222222"));
        assertEq(keccak256(results[1]), keccak256(hex"33333333"));
        assertEq(keccak256(results[2]), keccak256(hex"44444444"));
    }

    function test_batchCall_withValue() external {
        administeredAgent.__addActor(actor);

        address[] memory targets = new address[](3);
        targets[0] = makeAddr("target1");
        targets[1] = makeAddr("target2");
        targets[2] = makeAddr("target2");

        bytes[] memory data = new bytes[](3);
        data[0] = hex"12345678";
        data[1] = hex"87654321";
        data[2] = hex"11111111";

        uint256[] memory values = new uint256[](3);
        values[0] = 0.2 ether;
        values[1] = 0;
        values[2] = 0.5 ether;

        vm.deal(actor, 0.7 ether);

        vm.mockCall(targets[0],   0.2 ether, data[0], hex"22222222");
        vm.expectCall(targets[0], 0.2 ether, data[0]);
        vm.mockCall(targets[1],   0 ether,   data[1], hex"33333333");
        vm.expectCall(targets[1], 0 ether,   data[1]);
        vm.mockCall(targets[2],   0.5 ether, data[2], hex"44444444");
        vm.expectCall(targets[2], 0.5 ether, data[2]);

        vm.prank(actor);
        bytes[] memory results = administeredAgent.batchCall{ value: 0.7 ether }(targets, data, values);

        assertEq(results.length, 3);

        assertEq(keccak256(results[0]), keccak256(hex"22222222"));
        assertEq(keccak256(results[1]), keccak256(hex"33333333"));
        assertEq(keccak256(results[2]), keccak256(hex"44444444"));
    }

    /**********************************************************************************************/
    /*** sendValue Tests                                                                        ***/
    /**********************************************************************************************/

    function test_sendValue_notActor() external {
        vm.expectRevert(IAdministeredAgent.NotActor.selector);

        vm.prank(unauthorized);
        administeredAgent.sendValue(makeAddr("recipient"), 1 ether);
    }

    function test_sendValue() external {
        administeredAgent.__addActor(actor);

        address recipient = makeAddr("recipient");

        vm.deal(address(administeredAgent), 1 ether);

        vm.prank(actor);
        administeredAgent.sendValue(recipient, 0.5 ether);

        assertEq(address(administeredAgent).balance, 0.5 ether);
        assertEq(recipient.balance,                  0.5 ether);
    }

    /**********************************************************************************************/
    /*** adminCount Tests                                                                       ***/
    /**********************************************************************************************/

    function test_adminCount() external {
        assertEq(administeredAgent.adminCount(), 1);

        administeredAgent.__addAdmin(otherAdmin);

        assertEq(administeredAgent.adminCount(), 2);

        administeredAgent.__removeAdmin(otherAdmin);

        assertEq(administeredAgent.adminCount(), 1);
    }

    /**********************************************************************************************/
    /*** actorCount Tests                                                                       ***/
    /**********************************************************************************************/

    function test_actorCount() external {
        assertEq(administeredAgent.actorCount(), 0);

        administeredAgent.__addActor(actor);

        assertEq(administeredAgent.actorCount(), 1);

        administeredAgent.__removeActor(actor);

        assertEq(administeredAgent.actorCount(), 0);
    }

    /**********************************************************************************************/
    /*** grantorCount Tests                                                                     ***/
    /**********************************************************************************************/

    function test_grantorCount() external {
        assertEq(administeredAgent.grantorCount(), 0);

        administeredAgent.__addGrantor(grantor);

        assertEq(administeredAgent.grantorCount(), 1);

        administeredAgent.__removeGrantor(grantor);

        assertEq(administeredAgent.grantorCount(), 0);
    }

    /**********************************************************************************************/
    /*** revokerCount Tests                                                                     ***/
    /**********************************************************************************************/

    function test_revokerCount() external {
        assertEq(administeredAgent.revokerCount(), 0);

        administeredAgent.__addRevoker(revoker);

        assertEq(administeredAgent.revokerCount(), 1);

        administeredAgent.__removeRevoker(revoker);

        assertEq(administeredAgent.revokerCount(), 0);
    }

    /**********************************************************************************************/
    /*** getAdmin Tests                                                                         ***/
    /**********************************************************************************************/

    function test_getAdmin() external {
        administeredAgent.__addAdmin(otherAdmin);

        assertEq(administeredAgent.getAdmin(0), admin);
        assertEq(administeredAgent.getAdmin(1), otherAdmin);
    }

    /**********************************************************************************************/
    /*** getActor Tests                                                                         ***/
    /**********************************************************************************************/

    function test_getActor() external {
        address otherActor = makeAddr("otherActor");

        administeredAgent.__addActor(actor);
        administeredAgent.__addActor(otherActor);

        assertEq(administeredAgent.getActor(0), actor);
        assertEq(administeredAgent.getActor(1), otherActor);
    }

    /**********************************************************************************************/
    /*** getGrantor Tests                                                                       ***/
    /**********************************************************************************************/

    function test_getGrantor() external {
        address otherGrantor = makeAddr("otherGrantor");

        administeredAgent.__addGrantor(grantor);
        administeredAgent.__addGrantor(otherGrantor);

        assertEq(administeredAgent.getGrantor(0), grantor);
        assertEq(administeredAgent.getGrantor(1), otherGrantor);
    }

    /**********************************************************************************************/
    /*** getRevoker Tests                                                                       ***/
    /**********************************************************************************************/

    function test_getRevoker() external {
        address otherRevoker = makeAddr("otherRevoker");

        administeredAgent.__addRevoker(revoker);
        administeredAgent.__addRevoker(otherRevoker);

        assertEq(administeredAgent.getRevoker(0), revoker);
        assertEq(administeredAgent.getRevoker(1), otherRevoker);
    }

    /**********************************************************************************************/
    /*** getIsAdmin Tests                                                                       ***/
    /**********************************************************************************************/

    function test_getIsAdmin() external view {
        assertEq(administeredAgent.getIsAdmin(admin),        true);
        assertEq(administeredAgent.getIsAdmin(unauthorized), false);
    }

    /**********************************************************************************************/
    /*** getIsActor Tests                                                                       ***/
    /**********************************************************************************************/

    function test_getIsActor() external {
        assertEq(administeredAgent.getIsActor(actor), false);

        administeredAgent.__addActor(actor);

        assertEq(administeredAgent.getIsActor(actor), true);
    }

    /**********************************************************************************************/
    /*** getIsGrantor Tests                                                                     ***/
    /**********************************************************************************************/

    function test_getIsGrantor() external {
        assertEq(administeredAgent.getIsGrantor(grantor), false);

        administeredAgent.__addGrantor(grantor);

        assertEq(administeredAgent.getIsGrantor(grantor), true);
    }

    /**********************************************************************************************/
    /*** getIsRevoker Tests                                                                     ***/
    /**********************************************************************************************/

    function test_getIsRevoker() external {
        assertEq(administeredAgent.getIsRevoker(revoker), false);

        administeredAgent.__addRevoker(revoker);

        assertEq(administeredAgent.getIsRevoker(revoker), true);
    }

}
