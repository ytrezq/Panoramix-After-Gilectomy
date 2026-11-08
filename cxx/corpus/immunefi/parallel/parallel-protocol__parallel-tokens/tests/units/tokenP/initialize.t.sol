// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "tests/Units.t.sol";

contract TokenP_Initialize_Units_Test is Units_Test {

    function test_Initialize() external view {
        assertEq(aEURp.authority(), address(accessManager));
        assertEq(aEURp.name(), "aEURp");
        assertEq(aEURp.symbol(), "aEURp");
        assertEq(aEURp.decimals(), 18);
    }

    function test_revertWhen_AccessManagerIsAddressZero() external {
        TokenP tokenP = new TokenP();
        vm.expectRevert(abi.encodeWithSelector(CommonErrorsLib.AddressZero.selector));
        new ERC1967Proxy(address(tokenP), abi.encodeWithSelector(TokenP.initialize.selector, "aEURp", "aEURp", address(0)));
    }

    function test_revertWhen_AlreadyInitialized() external {
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        aEURp.initialize(
            "aEURp",
            "aEURp",
            address(accessManager)
        );
    }
}
