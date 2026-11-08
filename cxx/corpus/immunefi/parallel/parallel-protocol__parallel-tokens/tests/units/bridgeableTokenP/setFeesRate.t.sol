// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import "tests/Units.t.sol";

contract BridgeableToken_SetFeesRate_Units_Test is Units_Test {
    function test_SetFeesRate() external {
        vm.startPrank(users.guardian.addr);
        vm.expectEmit(address(aBridgeableTokenp));
        emit BridgeableTokenP_EventsLib.FeesRateSet(DEFAULT_FEE_RATE);
        accessManager.execute(address(aBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setFeesRate.selector, DEFAULT_FEE_RATE));
        assertEq(aBridgeableTokenp.getFeesRate(), DEFAULT_FEE_RATE);
    }

    function test_RevertWhen_CallerNotOwner() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, users.hacker.addr));
        aBridgeableTokenp.setFeesRate(DEFAULT_FEE_RATE);
    }

    function test_RevertWhen_ValueExceedMaxFeeAllowed() external {
        vm.startPrank(users.guardian.addr);
        vm.expectRevert(abi.encodeWithSelector(BridgeableTokenP_ErrorsLib.MaxFeesRateExceeded.selector));
        accessManager.execute(address(aBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setFeesRate.selector, ContractConstantsLib.MAX_FEE + 1));
    }
}
