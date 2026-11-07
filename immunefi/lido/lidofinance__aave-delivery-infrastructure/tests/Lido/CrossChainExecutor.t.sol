// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IExecutorBase} from "../../src/Lido/contracts/interfaces/IExecutorBase.sol";
import {CrossChainExecutor} from "../../src/Lido/contracts/CrossChainExecutor.sol";
import {BridgeExecutorBase} from "../../src/Lido/contracts/BridgeExecutorBase.sol";

import '../BaseTest.sol';

contract CrossChainExecutorTest is BaseTest {
  address public constant CROSS_CHAIN_CONTROLLER = address(123);
  address public constant GOVERNANCE_EXECUTOR = address(1234);
  uint256 public constant GOVERNANCE_CHAIN_ID = 1;

  uint256 public originalDelay = 0;
  uint256 public originalMaximumDelay = 1;
  uint256 public originalMinimumDelay = 0;
  uint256 public originalGracePeriod = 86400;
  address public originalGuardian = address(0);

  CrossChainExecutor public crossChainExecutor;

  event MessageReceived(address indexed originSender, uint256 indexed originChainId, bytes message);

  event ActionsSetQueued(
    uint256 indexed id,
    address[] targets,
    uint256[] values,
    string[] signatures,
    bytes[] calldatas,
    bool[] withDelegatecalls,
    uint256 executionTime
  );

  event DelayUpdate(uint256 oldDelay, uint256 newDelay);
  event GracePeriodUpdate(uint256 oldGracePeriod, uint256 newGracePeriod);
  event MinimumDelayUpdate(uint256 oldMinimumDelay, uint256 newMinimumDelay);
  event MaximumDelayUpdate(uint256 oldMaximumDelay, uint256 newMaximumDelay);
  event GuardianUpdate(address oldGuardian, address newGuardian);

  event ActionsSetExecuted(
    uint256 indexed id,
    address indexed initiatorExecution,
    bytes[] returnedData
  );

  event ActionsSetCanceled(uint256 indexed id);

  function setUp() public {
    crossChainExecutor = new CrossChainExecutor(
      CROSS_CHAIN_CONTROLLER,
      GOVERNANCE_EXECUTOR,
      GOVERNANCE_CHAIN_ID,
      originalDelay,
      originalGracePeriod,
      originalMinimumDelay,
      originalMaximumDelay,
      originalGuardian
    );
  }

  function test_CCE_constructor() public {
    vm.expectEmit();

    emit DelayUpdate(0, originalDelay);
    emit GracePeriodUpdate(0, originalGracePeriod);
    emit MinimumDelayUpdate(0, originalMinimumDelay);
    emit MaximumDelayUpdate(0, originalMaximumDelay);
    emit GuardianUpdate(address(0), originalGuardian);

    CrossChainExecutor cce = new CrossChainExecutor(
      CROSS_CHAIN_CONTROLLER,
      GOVERNANCE_EXECUTOR,
      GOVERNANCE_CHAIN_ID,
      originalDelay,
      originalGracePeriod,
      originalMinimumDelay,
      originalMaximumDelay,
      originalGuardian
    );

    assertEq(cce.getCrossChainController(), CROSS_CHAIN_CONTROLLER);
    assertEq(cce.getEthereumGovernanceExecutor(), GOVERNANCE_EXECUTOR);
    assertEq(cce.getEthereumGovernanceChainId(), GOVERNANCE_CHAIN_ID);

    assertEq(cce.getDelay(), originalDelay);
    assertEq(cce.getGracePeriod(), originalGracePeriod);
    assertEq(cce.getMinimumDelay(), originalMinimumDelay);
    assertEq(cce.getMaximumDelay(), originalMaximumDelay);
    assertEq(cce.getGuardian(), originalGuardian);
  }

  function test_CCE_receiveCrossChainMessage_RevertsWithInvalidCaller() public {
    vm.expectRevert(CrossChainExecutor.InvalidCaller.selector);
    crossChainExecutor.receiveCrossChainMessage(GOVERNANCE_EXECUTOR, GOVERNANCE_CHAIN_ID, abi.encode('0x1234'));
  }

  function test_CCE_receiveCrossChainMessage_RevertsWithInvalidSenderAddress() public {
    vm.prank(CROSS_CHAIN_CONTROLLER, address(0));

    vm.expectRevert(CrossChainExecutor.InvalidSenderAddress.selector);
    crossChainExecutor.receiveCrossChainMessage(CROSS_CHAIN_CONTROLLER, GOVERNANCE_CHAIN_ID, abi.encode('0x1234'));
  }

  function test_CCE_receiveCrossChainMessage_RevertsWithInvalidSenderChainId() public {
    vm.prank(CROSS_CHAIN_CONTROLLER, address(0));

    vm.expectRevert(CrossChainExecutor.InvalidSenderChainId.selector);
    crossChainExecutor.receiveCrossChainMessage(GOVERNANCE_EXECUTOR, 0, abi.encode('0x1234'));
  }

  function test_CCE_receiveCrossChainMessage_EmitsActionsSetQueued() public {
    vm.prank(CROSS_CHAIN_CONTROLLER, address(0));

    address[] memory addresses = new address[](1);
    uint256[] memory values = new uint256[](1);
    string[] memory signatures = new string[](1);
    bytes[] memory calldatas = new bytes[](1);
    bool[] memory withDelegatecalls = new bool[](1);

    addresses[0] = address(0);
    values[0] = 0;
    signatures[0] = 'test(string)';
    calldatas[0] = abi.encode('This is an encoded message...');
    withDelegatecalls[0] = false;

    bytes memory message = abi.encode(addresses, values, signatures, calldatas, withDelegatecalls);

    vm.expectEmit();
    emit MessageReceived(GOVERNANCE_EXECUTOR, GOVERNANCE_CHAIN_ID, message);
    emit ActionsSetQueued(0, addresses, values, signatures, calldatas, withDelegatecalls, 1);

    crossChainExecutor.receiveCrossChainMessage(GOVERNANCE_EXECUTOR, GOVERNANCE_CHAIN_ID, message);
  }

  function test_CCE_receiveCrossChainMessage_RevertsWithEmptyTargets() public {
    vm.prank(CROSS_CHAIN_CONTROLLER, address(0));

    address[] memory addresses = new address[](0);
    uint256[] memory values = new uint256[](1);
    string[] memory signatures = new string[](1);
    bytes[] memory calldatas = new bytes[](1);
    bool[] memory withDelegatecalls = new bool[](1);

    values[0] = 0;
    signatures[0] = 'test(string)';
    calldatas[0] = abi.encode('This is an encoded message...');
    withDelegatecalls[0] = false;

    bytes memory message = abi.encode(addresses, values, signatures, calldatas, withDelegatecalls);

    vm.expectRevert(IExecutorBase.EmptyTargets.selector);
    crossChainExecutor.receiveCrossChainMessage(GOVERNANCE_EXECUTOR, GOVERNANCE_CHAIN_ID, message);
  }

  function test_CCE_receiveCrossChainMessage_RevertsWithInconsistentParamsLength() public {
    vm.prank(CROSS_CHAIN_CONTROLLER, address(0));

    address[] memory addresses = new address[](2);
    uint256[] memory values = new uint256[](1);
    string[] memory signatures = new string[](1);
    bytes[] memory calldatas = new bytes[](1);
    bool[] memory withDelegatecalls = new bool[](1);

    addresses[0] = address(0);
    addresses[1] = address(1); // extra address
    values[0] = 0;
    signatures[0] = 'test(string)';
    calldatas[0] = abi.encode('This is an encoded message...');
    withDelegatecalls[0] = false;

    bytes memory message = abi.encode(addresses, values, signatures, calldatas, withDelegatecalls);

    vm.expectRevert(IExecutorBase.InconsistentParamsLength.selector);
    crossChainExecutor.receiveCrossChainMessage(GOVERNANCE_EXECUTOR, GOVERNANCE_CHAIN_ID, message);
  }

  function test_CCE_receiveCrossChainMessage_RevertsWithDuplicateAction() public {
    vm.prank(CROSS_CHAIN_CONTROLLER, address(0));

    address[] memory addresses = new address[](1);
    uint256[] memory values = new uint256[](1);
    string[] memory signatures = new string[](1);
    bytes[] memory calldatas = new bytes[](1);
    bool[] memory withDelegatecalls = new bool[](1);

    addresses[0] = address(0);
    values[0] = 0;
    signatures[0] = 'test(string)';
    calldatas[0] = abi.encode('This is an encoded message...');
    withDelegatecalls[0] = false;

    bytes memory message = abi.encode(addresses, values, signatures, calldatas, withDelegatecalls);

    crossChainExecutor.receiveCrossChainMessage(GOVERNANCE_EXECUTOR, GOVERNANCE_CHAIN_ID, message);

    vm.prank(CROSS_CHAIN_CONTROLLER, address(0));
    vm.expectRevert(IExecutorBase.DuplicateAction.selector);
    crossChainExecutor.receiveCrossChainMessage(GOVERNANCE_EXECUTOR, GOVERNANCE_CHAIN_ID, message);
  }

  function test_CCE_receiveCrossChainMessage_Queued() public {
    vm.prank(CROSS_CHAIN_CONTROLLER, address(0));

    address[] memory addresses = new address[](1);
    uint256[] memory values = new uint256[](1);
    string[] memory signatures = new string[](1);
    bytes[] memory calldatas = new bytes[](1);
    bool[] memory withDelegatecalls = new bool[](1);

    addresses[0] = address(0);
    values[0] = 0;
    signatures[0] = 'test(string)';
    calldatas[0] = abi.encode('This is an encoded message...');
    withDelegatecalls[0] = false;

    bytes memory message = abi.encode(addresses, values, signatures, calldatas, withDelegatecalls);

    emit ActionsSetQueued(0, addresses, values, signatures, calldatas, withDelegatecalls, 1);

    crossChainExecutor.receiveCrossChainMessage(GOVERNANCE_EXECUTOR, GOVERNANCE_CHAIN_ID, message);
  }

  function test_CCE_updateGuardian_Reverts() public {
    vm.expectRevert(IExecutorBase.OnlyCallableByThis.selector);
    crossChainExecutor.updateGuardian(address(1));
  }


  function test_CCE_updateGuardian() public {
    vm.startPrank(address(crossChainExecutor));
    vm.expectEmit();

    emit GuardianUpdate(originalGuardian, address(1));

    crossChainExecutor.updateGuardian(address(1));
    assertEq(crossChainExecutor.getGuardian(), address(1));
  }

  function test_CCE_updateDelay_Reverts() public {
    vm.expectRevert(IExecutorBase.OnlyCallableByThis.selector);
    crossChainExecutor.updateDelay(0);

    vm.startPrank(address(crossChainExecutor));

    crossChainExecutor.updateMaximumDelay(10);
    crossChainExecutor.updateDelay(5);
    crossChainExecutor.updateMinimumDelay(1);

    vm.expectRevert(IExecutorBase.DelayShorterThanMin.selector);
    crossChainExecutor.updateDelay(0);

    vm.expectRevert(IExecutorBase.DelayLongerThanMax.selector);
    crossChainExecutor.updateDelay(11);
  }

  function test_CCE_updateDelay() public {
    vm.startPrank(address(crossChainExecutor));

    crossChainExecutor.updateMaximumDelay(10);
    crossChainExecutor.updateDelay(5);
    crossChainExecutor.updateMinimumDelay(1);

    vm.expectEmit();
    emit DelayUpdate(5, 7);

    crossChainExecutor.updateDelay(7);
    assertEq(crossChainExecutor.getDelay(), 7);
  }

  function test_CCE_updateMinimumDelay_Reverts() public {
    vm.expectRevert(IExecutorBase.OnlyCallableByThis.selector);
    crossChainExecutor.updateMinimumDelay(0);

    vm.startPrank(address(crossChainExecutor));

    vm.expectRevert(IExecutorBase.MinimumDelayTooLong.selector);
    crossChainExecutor.updateMinimumDelay(1); // 1 > 0 (current delay)
  }

  function test_CCE_updateMinimumDelay() public {
    vm.startPrank(address(crossChainExecutor));

    crossChainExecutor.updateMaximumDelay(10);
    crossChainExecutor.updateDelay(5);

    vm.expectEmit();

    emit MinimumDelayUpdate(0, 1);

    crossChainExecutor.updateMinimumDelay(1);
    assertEq(crossChainExecutor.getMinimumDelay(), 1);
  }

  function test_CCE_updateMaximumDelay_Reverts() public {
    vm.expectRevert(IExecutorBase.OnlyCallableByThis.selector);
    crossChainExecutor.updateMaximumDelay(0);

    vm.startPrank(address(crossChainExecutor));

    vm.expectRevert(IExecutorBase.MaximumDelayTooShort.selector);
    crossChainExecutor.updateMaximumDelay(0); // 0 < 1 (current delay)
  }

  function test_CCE_updateMaximumDelay() public {
    vm.startPrank(address(crossChainExecutor));

    vm.expectEmit();

    emit MaximumDelayUpdate(1, 10);

    crossChainExecutor.updateMaximumDelay(10);
    assertEq(crossChainExecutor.getMaximumDelay(), 10);
  }

  function test_CCE_updateGracePeriod_Reverts() public {
    vm.expectRevert(IExecutorBase.OnlyCallableByThis.selector);
    crossChainExecutor.updateGracePeriod(86400);

    vm.startPrank(address(crossChainExecutor));

    vm.expectRevert(IExecutorBase.GracePeriodTooShort.selector);
    crossChainExecutor.updateGracePeriod(0);
  }

  function test_CCE_updateGracePeriod() public {
    vm.startPrank(address(crossChainExecutor));

    vm.expectEmit();

    emit GracePeriodUpdate(86400, 86401);

    crossChainExecutor.updateGracePeriod(86401);
    assertEq(crossChainExecutor.getGracePeriod(), 86401);
  }

  function test_CCE_getActionsSetCount() public {
    assertEq(crossChainExecutor.getActionsSetCount(), 0);

    queueAction();

    assertEq(crossChainExecutor.getActionsSetCount(), 1);
  }

  function test_CCE_getActionsSetById() public {
    queueAction();

    IExecutorBase.ActionsSet memory set = crossChainExecutor.getActionsSetById(0);

    assertEq(set.targets[0], address(0));
    assertEq(set.values[0], 0);
    assertEq(set.signatures[0], 'test(string)');
    assertEq(set.calldatas[0], abi.encode('This is an encoded message...'));
    assertEq(set.withDelegatecalls[0], false);
    assertEq(set.executionTime, 1);
    assertEq(set.executed, false);
    assertEq(set.canceled, false);
  }

  function test_CCE_getCurrentState_Reverts() public {
    vm.expectRevert(IExecutorBase.InvalidActionsSetId.selector);
    crossChainExecutor.getCurrentState(0);
  }

  function test_CCE_getCurrentState() public {
    queueAction();

    IExecutorBase.ActionsSetState state = crossChainExecutor.getCurrentState(0);

    assertEq(uint8(state), uint8(IExecutorBase.ActionsSetState.Queued));

    skip(originalGracePeriod + 1);

    state = crossChainExecutor.getCurrentState(0);

    assertEq(uint8(state), uint8(IExecutorBase.ActionsSetState.Expired));
  }

  function test_CCE_execute_Reverts() public {
    queueAction();

    rewind(1);

    vm.expectRevert(IExecutorBase.TimelockNotFinished.selector);
    crossChainExecutor.execute(0);

    skip(originalGracePeriod + 2);

    vm.expectRevert(IExecutorBase.OnlyQueuedActions.selector);
    crossChainExecutor.execute(0);
  }

  function test_CCE_execute_RevertsWithInsufficientBalance() public {
    address[] memory addresses = new address[](1);
    uint256[] memory values = new uint256[](1);
    string[] memory signatures = new string[](1);
    bytes[] memory calldatas = new bytes[](1);
    bool[] memory withDelegatecalls = new bool[](1);

    addresses[0] = address(0);
    values[0] = 1;
    signatures[0] = 'test(string)';
    calldatas[0] = abi.encode('This is an encoded message...');
    withDelegatecalls[0] = false;

    bytes memory message = abi.encode(addresses, values, signatures, calldatas, withDelegatecalls);

    vm.prank(CROSS_CHAIN_CONTROLLER, address(0));
    crossChainExecutor.receiveCrossChainMessage(GOVERNANCE_EXECUTOR, GOVERNANCE_CHAIN_ID, message);

    vm.expectRevert(IExecutorBase.InsufficientBalance.selector);
    vm.prank(CROSS_CHAIN_CONTROLLER, address(0));

    crossChainExecutor.execute(0);
  }

  function test_CCE_execute_StatusChecked() public {
    queueAction();

    vm.expectEmit();

    emit ActionsSetExecuted(0, CROSS_CHAIN_CONTROLLER, new bytes[](1));

    vm.prank(CROSS_CHAIN_CONTROLLER, address(0));
    crossChainExecutor.execute(0);

    IExecutorBase.ActionsSetState state = crossChainExecutor.getCurrentState(0);

    assertEq(uint8(state), uint8(IExecutorBase.ActionsSetState.Executed));
  }

  function test_CCE_execute_NoSignature() public {
    address[] memory addresses = new address[](1);
    uint256[] memory values = new uint256[](1);
    string[] memory signatures = new string[](1);
    bytes[] memory calldatas = new bytes[](1);
    bool[] memory withDelegatecalls = new bool[](1);

    addresses[0] = address(0);
    values[0] = 0;
    signatures[0] = '';
    calldatas[0] = abi.encode('This is an encoded message...');
    withDelegatecalls[0] = false;

    bytes memory message = abi.encode(addresses, values, signatures, calldatas, withDelegatecalls);

    vm.prank(CROSS_CHAIN_CONTROLLER, address(0));
    crossChainExecutor.receiveCrossChainMessage(GOVERNANCE_EXECUTOR, GOVERNANCE_CHAIN_ID, message);

    vm.expectEmit();

    emit ActionsSetExecuted(0, CROSS_CHAIN_CONTROLLER, new bytes[](1));

    vm.prank(CROSS_CHAIN_CONTROLLER, address(0));
    crossChainExecutor.execute(0);
  }

  function test_CCE_execute_WithDelegatecall() public {
    address[] memory addresses = new address[](1);
    uint256[] memory values = new uint256[](1);
    string[] memory signatures = new string[](1);
    bytes[] memory calldatas = new bytes[](1);
    bool[] memory withDelegatecalls = new bool[](1);

    addresses[0] = address(0);
    values[0] = 1;
    signatures[0] = 'test(string)';
    calldatas[0] = abi.encode('This is an encoded message...');
    withDelegatecalls[0] = true;

    bytes memory message = abi.encode(addresses, values, signatures, calldatas, withDelegatecalls);

    vm.prank(CROSS_CHAIN_CONTROLLER, address(0));
    crossChainExecutor.receiveCrossChainMessage(GOVERNANCE_EXECUTOR, GOVERNANCE_CHAIN_ID, message);

    vm.expectEmit();

    emit ActionsSetExecuted(0, CROSS_CHAIN_CONTROLLER, new bytes[](1));

    vm.prank(CROSS_CHAIN_CONTROLLER, address(0));
    vm.deal(address(crossChainExecutor), 10 ether); // Test branch with delegatecall and value
    crossChainExecutor.execute(0);
  }

  function test_CCE_execute_UnsuccessfulResults () public {
    RevertingTargetMock target = new RevertingTargetMock();

    address[] memory addresses = new address[](1);
    uint256[] memory values = new uint256[](1);
    string[] memory signatures = new string[](1);
    bytes[] memory calldatas = new bytes[](1);
    bool[] memory withDelegatecalls = new bool[](1);

    addresses[0] = address(target);
    values[0] = 0;
    signatures[0] = 'test(string)';
    calldatas[0] = abi.encode('This is an encoded message...');
    withDelegatecalls[0] = false;

    bytes memory message = abi.encode(addresses, values, signatures, calldatas, withDelegatecalls);

    vm.prank(CROSS_CHAIN_CONTROLLER, address(0));
    crossChainExecutor.receiveCrossChainMessage(GOVERNANCE_EXECUTOR, GOVERNANCE_CHAIN_ID, message);

    vm.expectRevert('RevertingTargetMock');
    vm.prank(address(0), address(0));
    crossChainExecutor.execute(0);
  }

  function test_CCE_execute_UnsuccessfulResultsWithNoMessage () public {
    RevertingWithNoMessageTargetMock target = new RevertingWithNoMessageTargetMock();

    address[] memory addresses = new address[](1);
    uint256[] memory values = new uint256[](1);
    string[] memory signatures = new string[](1);
    bytes[] memory calldatas = new bytes[](1);
    bool[] memory withDelegatecalls = new bool[](1);

    addresses[0] = address(target);
    values[0] = 0;
    signatures[0] = 'test()';
    calldatas[0] = abi.encode();
    withDelegatecalls[0] = false;

    bytes memory message = abi.encode(addresses, values, signatures, calldatas, withDelegatecalls);

    vm.prank(CROSS_CHAIN_CONTROLLER, address(0));
    crossChainExecutor.receiveCrossChainMessage(GOVERNANCE_EXECUTOR, GOVERNANCE_CHAIN_ID, message);

    vm.expectRevert(IExecutorBase.FailedActionExecution.selector);
    vm.prank(address(0), address(0));
    crossChainExecutor.execute(0);
  }

  function test_CCE_cancel_Reverts() public {
    queueAction();

    vm.expectRevert(IExecutorBase.NotGuardian.selector);
    crossChainExecutor.cancel(0);

    skip(originalGracePeriod + 1);

    vm.startPrank(address(0), address(0)); // Guardian
    vm.expectRevert(IExecutorBase.OnlyQueuedActions.selector);

    crossChainExecutor.cancel(0);
  }

  function test_CCE_cancel_StatusChecked() public {
    queueAction();

    vm.startPrank(address(0), address(0)); // Guardian
    vm.expectEmit();

    emit ActionsSetCanceled(0);
    crossChainExecutor.cancel(0);

    IExecutorBase.ActionsSetState state = crossChainExecutor.getCurrentState(0);

    assertEq(uint8(state), uint8(IExecutorBase.ActionsSetState.Canceled));
  }

  function test_CCE_executeDelegateCall_Reverts() public {
    vm.expectRevert(IExecutorBase.OnlyCallableByThis.selector);
    crossChainExecutor.executeDelegateCall(address(0), abi.encode('0x1234'));
  }

  function test_CCE_executeDelegateCall() public {
    vm.startPrank(address(crossChainExecutor));
    (bool success,) = crossChainExecutor.executeDelegateCall(address(0), abi.encode('0x1234'));

    assertEq(success, true);
  }

  // Helper functions

  function queueAction() public {
    address[] memory addresses = new address[](1);
    uint256[] memory values = new uint256[](1);
    string[] memory signatures = new string[](1);
    bytes[] memory calldatas = new bytes[](1);
    bool[] memory withDelegatecalls = new bool[](1);

    addresses[0] = address(0);
    values[0] = 0;
    signatures[0] = 'test(string)';
    calldatas[0] = abi.encode('This is an encoded message...');
    withDelegatecalls[0] = false;

    bytes memory message = abi.encode(addresses, values, signatures, calldatas, withDelegatecalls);

    vm.prank(CROSS_CHAIN_CONTROLLER, address(0));
    crossChainExecutor.receiveCrossChainMessage(GOVERNANCE_EXECUTOR, GOVERNANCE_CHAIN_ID, message);
  }
}

contract RevertingTargetMock {
  function test(string memory) public pure {
    revert('RevertingTargetMock');
  }
}

contract RevertingWithNoMessageTargetMock {
  function test() public pure {
    revert();
  }
}
