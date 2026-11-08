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

  address immutable SEPOLIA_DAO_VOTING = 0x39A0EbdEE54cB319f4F42141daaBDb6ba25D341A;
  address immutable SEPOLIA_DAO_TOKEN = 0xC73cd4B2A7c1CBC5BF046eB4A7019365558ABF66;
  address immutable SEPOLIA_DAO_AGENT = 0x32A0E5828B62AAb932362a4816ae03b860b65e83;

  struct Action {
    address _to;
    bytes _calldata;
  }

  function TRANSACTION_NETWORK() public pure virtual override returns (uint256);

  function _execute(DeployerHelpers.Addresses memory addresses) internal override {
    _initiateNewVote(addresses);

    uint256 voteId = AragonVotingInterface(SEPOLIA_DAO_VOTING).votesLength() - 1;

    AragonVotingInterface(SEPOLIA_DAO_VOTING).vote(voteId, true, false);
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

  function _initiateNewVote(DeployerHelpers.Addresses memory addresses) internal {
    bytes memory _voteCallData = abi.encodeWithSignature(
      'newVote(bytes,string,bool,bool)',
      _buildOwnershipTransferMotion(addresses),
      'Vote to update Mock on Binance testnet',
      false,
      false
    );

    Action[] memory actions = new Action[](1);
    actions[0]._to = SEPOLIA_DAO_VOTING;
    actions[0]._calldata = _voteCallData;

    bytes memory evmScript = _encodeCallScript(actions);

    AragonTokenInterface(SEPOLIA_DAO_TOKEN).forward(evmScript);
  }

  function _buildOwnershipTransferMotion(DeployerHelpers.Addresses memory addresses) internal view returns (bytes memory) {
    DeployerHelpers.Addresses memory bnbAddresses = _getAddresses(TestNetChainIds.BNB_TESTNET);

    Action[] memory actions = new Action[](1);

    actions[0] = _agentExecute(
      0x32A0E5828B62AAb932362a4816ae03b860b65e83, // https://docs.lido.fi/deployed-contracts/sepolia#dao-contracts
      addresses.crossChainController,
      0,
      abi.encodeWithSignature('forwardMessage(uint256,address,uint256,bytes)',
        TestNetChainIds.BNB_TESTNET,
        bnbAddresses.executorProd,
        1000000,
        _buildBinanceOwnershipTransferMotion(bnbAddresses)
      )
    );

    return _encodeCallScript(actions);
  }

  function _buildBinanceOwnershipTransferMotion(DeployerHelpers.Addresses memory bnbAddresses) internal pure returns (bytes memory) {
    address[] memory addresses = new address[](2);
    addresses[0] = bnbAddresses.mockDestination;
    addresses[1] = bnbAddresses.mockDestination;

    uint256[] memory values = new uint256[](2);
    values[0] = uint256(0);
    values[1] = uint256(0);

    string[] memory signatures = new string[](2);
    signatures[0] = 'test(string)';
    signatures[1] = 'test(string)';

    bytes[] memory calldatas = new bytes[](2);
    calldatas[0] = abi.encode('This is an encoded message from DAO Vote to update Mock on Binance testnet... #1');
    calldatas[1] = abi.encode('This is an encoded message from DAO Vote to update Mock on Binance testnet... #2');

    bool[] memory withDelegatecalls = new bool[](2);
    withDelegatecalls[0] = false;
    withDelegatecalls[1] = false;

    return abi.encode(addresses, values, signatures, calldatas, withDelegatecalls);
  }
}

contract Ethereum_testnet is VoteAgentChangeScript {
  function TRANSACTION_NETWORK() public pure override returns (uint256) {
    return TestNetChainIds.ETHEREUM_SEPOLIA;
  }
}
