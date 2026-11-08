// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import "tests/Units.t.sol";

contract BridgeableToken_SetGlobalCreditLimit_Units_Test is Units_Test {
    uint256 newGlobalCreditLimit = 100_000_000e18;

    function test_SetGlobalCreditLimit() external {
        vm.startPrank(users.guardian.addr);
        vm.expectEmit(address(aBridgeableTokenp));
        emit BridgeableTokenP_EventsLib.GlobalCreditLimitSet(newGlobalCreditLimit);
        accessManager.execute(address(aBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setGlobalCreditLimit.selector, newGlobalCreditLimit));
        assertEq(aBridgeableTokenp.getGlobalCreditLimit(), newGlobalCreditLimit);
    }

    function test_RevertWhen_CallerNotOwner() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, users.hacker.addr));
        aBridgeableTokenp.setGlobalCreditLimit(newGlobalCreditLimit);
    }

    function test_RevertWhen_ValueOverflowMaxGlobalLimit() external {
        vm.startPrank(users.guardian.addr);
        vm.expectRevert(abi.encodeWithSelector(BridgeableTokenP_ErrorsLib.GlobalLimitOverFlow.selector));
        accessManager.execute(address(aBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setGlobalCreditLimit.selector, uint256(type(int256).max) + 1));
    }
}
