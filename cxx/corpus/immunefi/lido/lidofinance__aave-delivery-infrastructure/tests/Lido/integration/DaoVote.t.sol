pragma solidity ^0.8.19;

import 'forge-std/console2.sol';
import 'forge-std/Vm.sol';

import {IExecutorBase} from "../../../src/Lido/contracts/interfaces/IExecutorBase.sol";
import {ChainIds} from "../../../src/contracts/libs/ChainIds.sol";

import {BaseIntegrationTest} from "../BaseIntegrationTest.sol";

import {MockDestination} from "../utils/MockDestination.sol";

interface AragonTokenInterface {
  function forward(bytes calldata evmScript) external;
}

interface AragonVotingInterface {
  enum VotePhase {Main, Objection, Closed}

  function votesLength() external view returns (uint256);

  function vote(uint256 _voteId, bool _supports, bool _executesIfDecided) external;

  function executeVote(uint256 _voteId) external;

  function getVote(uint256 _voteId) external returns (
    bool open,
    bool executed,
    uint64 startDate,
    uint64 snapshotBlock,
    uint64 supportRequired,
    uint64 minAcceptQuorum,
    uint256 yea,
    uint256 nay,
    uint256 votingPower,
    bytes memory script,
    VotePhase phase
  );
}

contract DaoVoteIntegrationTest is BaseIntegrationTest {
  uint32 immutable DEFAULT_EXECUTOR_ID = 1;

  // https://docs.lido.fi/deployed-contracts/#dao-contracts
  address public constant LIDO_DAO_TOKEN = 0xf73a1260d222f447210581DDf212D915c09a3249;
  address public constant LIDO_DAO_VOTING = 0x2e59A20f205bB85a89C53f1936454680651E618e;

  struct Action {
    address _to;
    bytes _calldata;
  }

  struct Vote {
    bool open;
    bool executed;
    uint64 startDate;
    uint64 snapshotBlock;
    uint64 supportRequired;
    uint64 minAcceptQuorum;
    uint256 yea;
    uint256 nay;
    uint256 votingPower;
    uint64 scriptOffset;
    bytes script;
    uint8 phase;
  }

  function setUp() override public {
    super.setUp();

    vm.selectFork(ethFork);
    transferLinkTokens(ethCCCAddress);
  }

  function test_DaoVote_OnBinance() public {
    address BINANCE_DAO_AGENT = isRealDaoAgent ? crossChainAddresses.bnb.executorProd : crossChainAddresses.bnb.executorMock;

    string memory message = "Test voting";

    vm.selectFork(bnbFork);
    MockDestination mockDestination = new MockDestination(BINANCE_DAO_AGENT);
    address mockDestinationAddress = address(mockDestination);

    // Create a dao vote to call mock destination test function
    vm.selectFork(ethFork);
    bytes memory voteCallData = _buildBSCMockUpgradeMotion(mockDestinationAddress, message);
    _forwardVote(voteCallData, message);

    uint256 voteId = AragonVotingInterface(LIDO_DAO_VOTING).votesLength() - 1;

    // Vote and execute the dao vote
    vm.recordLogs();
    _voteAndExecute(voteId);

    Vm.Log[] memory entries = vm.getRecordedLogs();
    _validateTransactionForwardingSuccess(entries, 3);
    (bytes memory encodedTransaction) = _getTransactionFromLogs(entries);

    // Pass the message via adapters
    vm.selectFork(bnbFork);

    vm.recordLogs();
    _receiveDaoCrossChainMessage(
      crossChainAddresses.bnb.crossChainController,
      bnbAdapters,
      encodedTransaction,
      ChainIds.ETHEREUM
    );
    uint256 actionId = _getActionsSetQueued(vm.getRecordedLogs());

    // Execute the action received via a.DI
    IExecutorBase executor = IExecutorBase(crossChainAddresses.bnb.executorProd);

    vm.expectEmit();
    emit TestWorked(message);

    executor.execute(actionId);

    // Validate that the message was received by the mock destination
    assertEq(mockDestination.message(), message);
  }

  function _buildBSCMockUpgradeMotion(
    address _address,
    string memory _message
  ) internal view returns (bytes memory) {
    Action[] memory actions = new Action[](1);
    actions[0] = _agentExecute(
      LIDO_DAO_AGENT,
      crossChainAddresses.eth.crossChainController,
      0,
      abi.encodeWithSignature('forwardMessage(uint256,address,uint256,bytes)',
        ChainIds.BNB,
        crossChainAddresses.bnb.executorProd,
        getGasLimit(),
        _buildMockUpgradeMotion(_address, _message)
      )
    );

    return _encodeCallScript(actions);
  }

  function _voteAndExecute(
    uint256 _voteId
  ) internal {
    vm.prank(LIDO_DAO_AGENT); // DAO Agent - the biggest LDO holder
    AragonVotingInterface aragonVoting = AragonVotingInterface(LIDO_DAO_VOTING);

    aragonVoting.vote(_voteId, true, false);

    aragonVoting.getVote(_voteId);

    // 7 days to pass the voting period
    vm.warp(block.timestamp + 7 days);

    aragonVoting.getVote(_voteId);

    aragonVoting.executeVote(_voteId);
  }

  // Helpers

  function _encodeCallScript(Action[] memory _actions) internal pure returns (bytes memory) {
    bytes memory _script = abi.encodePacked(uint32(DEFAULT_EXECUTOR_ID));
    for (uint256 i = 0; i < _actions.length; i++) {
      address _to = _actions[i]._to;
      bytes memory _calldata = _actions[i]._calldata;

      _script = bytes.concat(
        _script,
        abi.encodePacked(address(_to)),
        abi.encodePacked(uint32(_calldata.length)),
        _calldata
      );
    }

    return _script;
  }

  function _agentExecute(address _agent, address _to, uint256 _value, bytes memory data) internal pure returns (Action memory) {
    bytes memory _calldata = abi.encodeWithSignature('execute(address,uint256,bytes)', _to, _value, data);

    return Action(_agent, _calldata);
  }

  function _forwardVote(
    bytes memory _data,
    string memory _name
  ) internal {
    Action[] memory actions = new Action[](1);

    actions[0]._to = LIDO_DAO_VOTING;
    actions[0]._calldata = abi.encodeWithSignature('newVote(bytes,string,bool,bool)', _data, _name, false, false);

    bytes memory evmScript = _encodeCallScript(actions);

    vm.prank(LIDO_DAO_AGENT); // DAO Agent - the biggest LDO holder
    AragonTokenInterface(LIDO_DAO_TOKEN).forward(evmScript);
  }

  // Utility functions

  function _getTransactionFromLogs(
    Vm.Log[] memory _logs
  ) internal pure returns (bytes memory encodedTransaction) {
    bytes32 signature = keccak256("TransactionForwardingAttempted(bytes32,bytes32,bytes,uint256,address,address,bool,bytes)");

    for (uint256 i = 0; i < _logs.length; i++) {
      if (_logs[i].topics[0] == signature && _logs[i].topics[3] == bytes32(uint(1))) {
        (, encodedTransaction,,,) = abi.decode(_logs[i].data, (bytes32, bytes, uint256, address, bytes));

        return (encodedTransaction);
      }
    }

    revert('TransactionForwardingAttempted not found');
  }
}
