// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import "tests/Units.t.sol";

contract BridgeableToken_SetDailyCreditLimit_Units_Test is Units_Test {
    uint256 newDailyCreditLimit = 100_000e18;

    function test_SetDailyCreditLimit() external {
        vm.startPrank(users.guardian.addr);
        vm.expectEmit(address(aBridgeableTokenp));
        emit BridgeableTokenP_EventsLib.DailyCreditLimitSet(newDailyCreditLimit);
        accessManager.execute(address(aBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setDailyCreditLimit.selector, newDailyCreditLimit));
        assertEq(aBridgeableTokenp.getDailyCreditLimit(), newDailyCreditLimit);
    }

    function test_RevertWhen_CallerNotOwner() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, users.hacker.addr));
        aBridgeableTokenp.setDailyCreditLimit(newDailyCreditLimit);
    }
}
