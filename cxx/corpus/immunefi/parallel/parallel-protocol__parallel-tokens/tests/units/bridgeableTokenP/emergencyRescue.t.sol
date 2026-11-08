// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import "tests/Units.t.sol";

contract BridgeableToken_EmergencyRescue_Units_Test is Units_Test {
    function setUp() public virtual override {
        super.setUp();
        deal(address(aEURp), address(aBridgeableTokenp), INITIAL_BALANCE);
        
        vm.startPrank(users.guardian.addr);
        accessManager.execute(address(aBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.pause.selector));
    }

    function test_EmergencyRescue() external {
        vm.startPrank(users.guardian.addr);
        accessManager.execute(address(aBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.emergencyRescue.selector, address(aEURp),users.guardian.addr, INITIAL_BALANCE));
        assertEq(aEURp.balanceOf(address(aBridgeableTokenp)), 0);
        assertEq(aEURp.balanceOf(users.guardian.addr), INITIAL_BALANCE);
    }

    function test_RevertWhen_CallerNotOwner() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, users.hacker.addr));
        aBridgeableTokenp.emergencyRescue(address(aEURp), users.hacker.addr, INITIAL_BALANCE);
    }

    modifier unpauseContract() {
        vm.startPrank(users.guardian.addr);
        accessManager.execute(address(aBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.unpause.selector));
        _;
    }

    function test_RevertWhen_ContractNotPaused() external unpauseContract {
        vm.startPrank(users.guardian.addr);
        vm.expectRevert(abi.encodeWithSelector(Pausable.ExpectedPause.selector));
        accessManager.execute(address(aBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.emergencyRescue.selector, address(aEURp),users.guardian.addr, INITIAL_BALANCE));
    }
}
