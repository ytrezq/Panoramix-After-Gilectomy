// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import "tests/Units.t.sol";

contract BridgeableToken_Unpause_Units_Test is Units_Test {
    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(users.guardian.addr);
        accessManager.execute(address(aBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.pause.selector));
    }

    function test_UnPause() external {
        vm.startPrank(users.guardian.addr);
        vm.expectEmit(address(aBridgeableTokenp));
        emit Pausable.Unpaused(address(accessManager));
        accessManager.execute(address(aBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.unpause.selector));
        assertFalse(aBridgeableTokenp.paused());
    }

    function test_RevertWhen_CallerNotOwner() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, users.hacker.addr));
        aBridgeableTokenp.unpause();
    }
}
