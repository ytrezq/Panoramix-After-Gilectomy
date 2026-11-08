// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import "tests/Units.t.sol";

contract BridgeableToken_SetDailyDebitLimit_Units_Test is Units_Test {
    uint256 newDailyDebitLimit = 100_000e18;

    function test_SetDailyDebitLimit() external {
        vm.startPrank(users.guardian.addr);
        vm.expectEmit(address(aBridgeableTokenp));
        emit BridgeableTokenP_EventsLib.DailyDebitLimitSet(newDailyDebitLimit);
        accessManager.execute(address(aBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setDailyDebitLimit.selector, newDailyDebitLimit));
        assertEq(aBridgeableTokenp.getDailyDebitLimit(), newDailyDebitLimit);
    }

    function test_RevertWhen_CallerNotOwner() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, users.hacker.addr));
        aBridgeableTokenp.setDailyDebitLimit(newDailyDebitLimit);
    }
}
