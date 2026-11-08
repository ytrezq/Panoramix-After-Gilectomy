// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import "tests/Units.t.sol";

contract BridgeableToken_ToggleIsolateMode_Units_Test is Units_Test {
    modifier prankOwner() {
        vm.startPrank(users.guardian.addr);
        _;
    }

    function test_ToggleIsolateMode_FromFalseToTrue() external prankOwner {
        vm.expectEmit(address(aBridgeableTokenp));
        emit BridgeableTokenP_EventsLib.IsolateModeToggled(true);
        accessManager.execute(address(aBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.toggleIsolateMode.selector));
        assertTrue(aBridgeableTokenp.getIsIsolateMode());
    }

    modifier initIsIsolateModeToFalse() {

        accessManager.execute(address(aBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.toggleIsolateMode.selector));
        _;
    }

    function test_ToggleIsolateMode_FromTrueToFalse() external prankOwner initIsIsolateModeToFalse {
        vm.expectEmit(address(aBridgeableTokenp));
        emit BridgeableTokenP_EventsLib.IsolateModeToggled(false);
        accessManager.execute(address(aBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.toggleIsolateMode.selector));
        assertFalse(aBridgeableTokenp.getIsIsolateMode());
    }

    function test_RevertWhen_CallerNotOwner() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, users.hacker.addr));
        aBridgeableTokenp.toggleIsolateMode();
    }
}
