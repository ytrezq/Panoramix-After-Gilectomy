// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;


import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";

import { TokenPMockV2 } from "tests/mock/TokenPMockV2.sol";
import "tests/Units.t.sol";

contract TokenP_UpgradeAndCall_Units_Test is Units_Test {
    TokenPMockV2 newTokenP = new TokenPMockV2();

    function test_UpgradeAndCall() external {
        vm.startPrank(users.dao.addr);
        aEURp.upgradeToAndCall(address(newTokenP),"");
        assertEq(TokenPMockV2(address(aEURp)).version(), 2);
    }

    function test_revertWhen_CallerIsNotAllowed() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        aEURp.upgradeToAndCall(address(newTokenP),"");
    }

}