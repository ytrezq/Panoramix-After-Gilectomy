// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract SideChainFeeCollector_Release_Integrations_Test is Integrations_Test {
    using OptionsBuilder for bytes;

    function test_SideChainFeeCollector_Release() external {
        vm.startPrank(users.admin.addr);
        par.mint(address(sideChainFeeCollector), INITIAL_BALANCE);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        sideChainFeeCollector.release(options, address(bridgeableTokenMock), address(mainFeeDistributor));

        assertEq(par.balanceOf(address(sideChainFeeCollector)), 0);
    }

    function test_SideChainFeeCollector_Release_RevertWhen_NotCallerNotAuthorized() external {
        vm.startPrank(users.hacker.addr);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        sideChainFeeCollector.release(options, address(bridgeableTokenMock), address(mainFeeDistributor));
    }

    function test_SideChainFeeCollector_Release_RevertWhen_AmountIsZero() external {
        vm.startPrank(users.admin.addr);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        vm.expectRevert(abi.encodeWithSelector(FeeCollectorCore.NothingToRelease.selector));
        sideChainFeeCollector.release(options, address(bridgeableTokenMock), address(mainFeeDistributor));
    }

    function test_SideChainFeeCollector_Release_RevertWhen_BridgeableTokenMismatch() external {
        vm.startPrank(users.admin.addr);
        address wrongBridgeableToken = makeAddr("wrongBridgeableToken");
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        vm.expectRevert(abi.encodeWithSelector(SideChainFeeCollector.BridgeableTokenMismatch.selector));
        sideChainFeeCollector.release(options, wrongBridgeableToken, address(mainFeeDistributor));
    }

    function test_SideChainFeeCollector_Release_RevertWhen_DestinationReceiverMismatch() external {
        vm.startPrank(users.admin.addr);
        address wrongDestinationReceiver = makeAddr("wrongDestinationReceiver");
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        vm.expectRevert(abi.encodeWithSelector(SideChainFeeCollector.DestinationReceiverMismatch.selector));
        sideChainFeeCollector.release(options, address(bridgeableTokenMock), wrongDestinationReceiver);
    }
}
