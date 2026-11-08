// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "tests/Units.t.sol";

contract FlashParallelToken_Initialize_Units_Test is Units_Test {

    function test_Initialize() external view {
        assertEq(flashParallelToken.authority(), address(accessManager));
        assertEq(flashParallelToken.flashLoanFeeRecipient(), users.feesRecipient.addr);
    }


    function test_revertWhen_AccessManagerIsAddressZero() external {
        FlashParallelToken flashParallelTokenImpl = new FlashParallelToken();
        vm.expectRevert(abi.encodeWithSelector(CommonErrorsLib.AddressZero.selector));
        new ERC1967Proxy(address(flashParallelTokenImpl), abi.encodeWithSelector(FlashParallelToken.initialize.selector, address(0), users.feesRecipient.addr));
    }


    function test_revertWhen_FlashLoanFeeRecipientIsAddressZero() external {
        FlashParallelToken flashParallelTokenImpl = new FlashParallelToken();
        vm.expectRevert(abi.encodeWithSelector(CommonErrorsLib.AddressZero.selector));
        new ERC1967Proxy(address(flashParallelTokenImpl), abi.encodeWithSelector(FlashParallelToken.initialize.selector, address(accessManager), address(0)));
    }

    function test_revertWhen_AlreadyInitialized() external {
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        flashParallelToken.initialize(address(accessManager), users.feesRecipient.addr);
    }

}