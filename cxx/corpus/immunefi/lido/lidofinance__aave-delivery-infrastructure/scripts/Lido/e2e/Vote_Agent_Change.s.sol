// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import 'forge-std/Script.sol';

import '../BaseScript.sol';

interface AragonTokenInterface {
  function forward(bytes calldata evmScript) external;
}

interface AragonVotingInterface {
  function votesLength() external view returns (uint256);

  function vote(uint256 _voteId, bool _supports, bool _executesIfDecided) external;

  function executeVote(uint256 _voteId) external;
}

abstract contract VoteAgentChangeScript is BaseScript {

  uint32 immutable DEFAULT_EXECUTOR_ID = 1;

  address immutable FAKE_DAO_VOTING = 0x124208720f804A9ded96F0CD532018614b8aE28d;
  address immutable FAKE_DAO_TOKEN = 0xdAc681011f846Af90AEbd11d0C9Cc6BCa70Dd636;

  struct Action {
    address _to;
    bytes _calldata;
  }

  function TRANSACTION_NETWORK() public pure virtual override returns (uint256);

  function _execute(DeployerHelpers.Addresses memory addresses) internal override {
    DeployerHelpers.Addresses memory bnbAddresses = _getAddresses(ChainIds.BNB);

    // STEP 1
    bytes memory bscUpdateVoteCallData = _buildBSCOwnershipTransferMotion(addresses, bnbAddresses);
    _initiateMockDAOVote(bscUpdateVoteCallData, 'Transfer ownership on BSC to new CCE');

    // STEP 2
    // bytes memory ethUpdateVoteCallData = _buildETHOwnershipTransferMotion(addresses);
    // _initiateMockDAOVote(ethUpdateVoteCallData, 'Transfer ownership on ETH to Lido DAO');

    // @changes - Decided to make the voting process manual on mainnet

    // @dev checking locally that voting works
    if (isLocalFork()) {
      uint256 voteId = AragonVotingInterface(FAKE_DAO_VOTING).votesLength() - 1;
      AragonVotingInterface(FAKE_DAO_VOTING).vote(voteId, true, false);

      vm.warp(block.timestamp + 1260); // 21 minutes to pass the voting period

      AragonVotingInterface(FAKE_DAO_VOTING).executeVote(voteId);
    }
  }

  function _agentExecute(address _agent, address _to, uint256 _value, bytes memory data) internal pure returns (Action memory) {
    bytes memory _calldata = abi.encodeWithSignature('execute(address,uint256,bytes)', _to, _value, data);

    return Action(_agent, _calldata);
  }

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

  function _initiateMockDAOVote(
    bytes memory _data,
    string memory _name
  ) internal {
    Action[] memory actions = new Action[](1);

    actions[0]._to = FAKE_DAO_VOTING;
    actions[0]._calldata = abi.encodeWithSignature('newVote(bytes,string,bool,bool)', _data, _name, false, false);

    bytes memory evmScript = _encodeCallScript(actions);

    AragonTokenInterface(FAKE_DAO_TOKEN).forward(evmScript);
  }

  function _buildBSCOwnershipTransferMotion(
    DeployerHelpers.Addresses memory _ethAddresses,
    DeployerHelpers.Addresses memory _bnbAddresses
  ) internal view returns (bytes memory) {
    address[] memory addresses = new address[](2);
    addresses[0] = _bnbAddresses.crossChainController;
    addresses[1] = _bnbAddresses.proxyAdmin;

    uint256[] memory values = new uint256[](2);
    values[0] = uint256(0);
    values[1] = uint256(0);

    string[] memory signatures = new string[](2);
    signatures[0] = 'transferOwnership(address)';
    signatures[1] = 'transferOwnership(address)';

    bytes[] memory calldatas = new bytes[](2);
    calldatas[0] = abi.encode(_bnbAddresses.executorProd);
    calldatas[1] = abi.encode(_bnbAddresses.executorProd);

    bool[] memory withDelegatecalls = new bool[](2);
    withDelegatecalls[0] = false;
    withDelegatecalls[1] = false;

    bytes memory motion = abi.encode(addresses, values, signatures, calldatas, withDelegatecalls);

    Action[] memory actions = new Action[](1);

    actions[0] = _agentExecute(
      Constants.LIDO_DAO_AGENT_FAKE,
      _ethAddresses.crossChainController,
      0,
      abi.encodeWithSignature('forwardMessage(uint256,address,uint256,bytes)',
        ChainIds.BNB,
        _bnbAddresses.executorMock,
        1000000,
        motion
      )
    );

    return _encodeCallScript(actions);
  }

  function _buildETHOwnershipTransferMotion(
    DeployerHelpers.Addresses memory addresses
  ) internal view returns (bytes memory) {

    Action[] memory actions = new Action[](4);

    address[] memory approveSenders = new address[](1);
    approveSenders[0] = Constants.LIDO_DAO_AGENT;

    actions[0] = _agentExecute(
      Constants.LIDO_DAO_AGENT_FAKE,
      addresses.crossChainController,
      0,
      abi.encodeWithSignature('approveSenders(address[])', approveSenders)
    );

    address[] memory removeSenders = new address[](1);
    removeSenders[0] = Constants.LIDO_DAO_AGENT_FAKE;

    actions[1] = _agentExecute(
      Constants.LIDO_DAO_AGENT_FAKE,
      addresses.crossChainController,
      0,
      abi.encodeWithSignature('removeSenders(address[])', removeSenders)
    );

    actions[2] = _agentExecute(
      Constants.LIDO_DAO_AGENT_FAKE,
      addresses.crossChainController,
      0,
      abi.encodeWithSignature('transferOwnership(address)', Constants.LIDO_DAO_AGENT)
    );

    actions[3] = _agentExecute(
      Constants.LIDO_DAO_AGENT_FAKE,
      addresses.proxyAdmin,
      0,
      abi.encodeWithSignature('transferOwnership(address)', Constants.LIDO_DAO_AGENT)
    );

    return _encodeCallScript(actions);
  }
}

contract Ethereum is VoteAgentChangeScript {
  function TRANSACTION_NETWORK() public pure override returns (uint256) {
    return ChainIds.ETHEREUM;
  }
}

contract Ethereum_local is Ethereum {
  function isLocalFork() public pure virtual override returns (bool) {
    return true;
  }
}
