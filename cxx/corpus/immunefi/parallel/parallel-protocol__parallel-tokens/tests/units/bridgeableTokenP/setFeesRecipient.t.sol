// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import "tests/Units.t.sol";

contract BridgeableToken_SetFeesRecipient_Units_Test is Units_Test {
    address newFeesRecipient = makeAddr("New Fees Recipient");

    function test_SetFeesRecipient() external {
        vm.startPrank(users.guardian.addr);
        vm.expectEmit(address(aBridgeableTokenp));
        emit BridgeableTokenP_EventsLib.FeesRecipientSet(newFeesRecipient);
        accessManager.execute(address(aBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setFeesRecipient.selector, newFeesRecipient));
        assertEq(aBridgeableTokenp.getFeesRecipient(), newFeesRecipient);
    }

    function test_RevertWhen_CallerNotOwner() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, users.hacker.addr));
        aBridgeableTokenp.setFeesRecipient(newFeesRecipient);
    }

    function test_RevertWhen_ValueIsAddressZero() external {
        vm.startPrank(users.guardian.addr);
        vm.expectRevert(abi.encodeWithSelector(CommonErrorsLib.AddressZero.selector));
        accessManager.execute(address(aBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setFeesRecipient.selector, address(0)));
    }
}
