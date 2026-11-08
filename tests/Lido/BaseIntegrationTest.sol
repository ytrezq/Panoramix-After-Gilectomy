pragma solidity ^0.8.19;

import 'forge-std/console2.sol';
import 'forge-std/Vm.sol';
import 'forge-std/StdJson.sol';

import {Envelope, EncodedEnvelope, Transaction, EncodedTransaction} from '../../src/contracts/libs/EncodingUtils.sol';
import {ICrossChainController} from "../../src/contracts/interfaces/ICrossChainController.sol";

import {IExecutorBase} from "../../src/Lido/contracts/interfaces/IExecutorBase.sol";

import {BaseTest} from "../BaseTest.sol";

import {BaseTestHelpers} from "./BaseTestHelpers.sol";
import {MockDestination} from "./utils/MockDestination.sol";

contract BaseIntegrationTest is BaseTest, BaseTestHelpers {
  using stdJson for string;

  string ENV = vm.envString('ENV');
  string REAL_DAO = vm.envString('REAL_DAO');

  uint256 public ethFork;
  uint256 public bnbFork;

  struct Addresses {
    address ccipAdapter;
    uint256 chainId;
    address crossChainController;
    address crossChainControllerImpl;
    address guardian;
    address hlAdapter;
    address lzAdapter;
    address mockDestination;
    address proxyAdmin;
    address wormholeAdapter;
    address executorMock;
    address executorProd;
  }

  struct CrossChainAddresses {
    Addresses eth;
    Addresses bnb;
  }

  struct CrossChainAddressFiles {
    string eth;
    string bnb;
  }

  CrossChainAddresses internal crossChainAddresses;

  event TestWorked(string message);

  address public ethCCCAddress;
  address[] public bnbAdapters = new address[](4);

  bool public isRealDaoAgent = false;

  function _getDeploymentFiles() internal view returns (CrossChainAddressFiles memory) {
    if (keccak256(abi.encodePacked(ENV)) == keccak256(abi.encodePacked("local"))) {
      return CrossChainAddressFiles({
        eth: './deployments/cc/local/eth.json',
        bnb: './deployments/cc/local/bnb.json'
      });
    }

    if (keccak256(abi.encodePacked(ENV)) == keccak256(abi.encodePacked("testnet"))) {
      return CrossChainAddressFiles({
        eth: './deployments/cc/testnet/sep.json',
        bnb: './deployments/cc/testnet/bnb_test.json'
      });
    }

    return CrossChainAddressFiles({
      eth: './deployments/cc/mainnet/eth.json',
      bnb: './deployments/cc/mainnet/bnb.json'
    });
  }

  function _decodeJson(string memory path, Vm vm) internal view returns (Addresses memory) {
    string memory persistedJson = vm.readFile(path);

    Addresses memory addresses = Addresses({
      proxyAdmin: abi.decode(persistedJson.parseRaw('.proxyAdmin'), (address)),
      guardian: abi.decode(persistedJson.parseRaw('.guardian'), (address)),
      crossChainController: abi.decode(persistedJson.parseRaw('.crossChainController'), (address)),
      crossChainControllerImpl: abi.decode(
        persistedJson.parseRaw('.crossChainControllerImpl'),
        (address)
      ),
      ccipAdapter: abi.decode(persistedJson.parseRaw('.ccipAdapter'), (address)),
      chainId: abi.decode(persistedJson.parseRaw('.chainId'), (uint256)),
      lzAdapter: abi.decode(persistedJson.parseRaw('.lzAdapter'), (address)),
      hlAdapter: abi.decode(persistedJson.parseRaw('.hlAdapter'), (address)),
      mockDestination: abi.decode(persistedJson.parseRaw('.mockDestination'), (address)),
      wormholeAdapter: abi.decode(persistedJson.parseRaw('.wormholeAdapter'), (address)),
      executorMock: abi.decode(persistedJson.parseRaw('.executorMock'), (address)),
      executorProd: abi.decode(persistedJson.parseRaw('.executorProd'), (address))
    });

    return addresses;
  }

  function setUp() virtual public {
    CrossChainAddressFiles memory files = _getDeploymentFiles();
    crossChainAddresses.eth = _decodeJson(files.eth, vm);
    crossChainAddresses.bnb = _decodeJson(files.bnb, vm);

    string memory ethForkName = 'ethereum';
    string memory bnbForkName = 'binance';

    if (keccak256(abi.encodePacked(ENV)) == keccak256(abi.encodePacked("local"))) {
      ethForkName = 'ethereum-local';
      bnbForkName = 'binance-local';
    }

    if (keccak256(abi.encodePacked(REAL_DAO)) == keccak256(abi.encodePacked("true"))) {
      isRealDaoAgent = true;
    }

    ethFork = vm.createFork(ethForkName);
    bnbFork = vm.createFork(bnbForkName);

    bnbAdapters[0] = crossChainAddresses.bnb.ccipAdapter;
    bnbAdapters[1] = crossChainAddresses.bnb.lzAdapter;
    bnbAdapters[2] = crossChainAddresses.bnb.hlAdapter;
    bnbAdapters[3] = crossChainAddresses.bnb.wormholeAdapter;

    ethCCCAddress = crossChainAddresses.eth.crossChainController;

    vm.selectFork(ethFork);
  }

  /**
    * @notice Send a message with the specified destination and message via a.DI
    * @param _crossChainController The address of the cross chain controller
    * @param _destination The destination address of the message
    * @param _destinationChainId The destination chain ID of the message
    * @param _message The message of the envelope
    */
  function _sendCrossChainTransactionAsDao(
    address _daoAgent,
    address _crossChainController,
    address _destination,
    uint256 _destinationChainId,
    bytes memory _message
  ) internal returns (ExtendedTransaction memory) {
    ICrossChainController crossChainController = ICrossChainController(_crossChainController);

    assertEq(crossChainController.isSenderApproved(_daoAgent), true);

    ExtendedTransaction memory extendedTx = _registerExtendedTransaction(
      crossChainController.getCurrentEnvelopeNonce(),
      crossChainController.getCurrentTransactionNonce(),
      _daoAgent,
      ETHEREUM_CHAIN_ID,
      _destination,
      _destinationChainId,
      _message
    );

    vm.recordLogs();
    vm.prank(_daoAgent);
    crossChainController.forwardMessage(
      _destinationChainId,
      _destination,
      getGasLimit(),
      _message
    );

    return extendedTx;
  }

  function _receiveDaoCrossChainMessage(
    address _crossChainController,
    address[] memory adapters,
    bytes memory _encodedTransaction,
    uint256 _originChainId
  ) internal {
    ICrossChainController targetCrossChainController = ICrossChainController(_crossChainController);

    vm.recordLogs();

    for (uint256 i = 0; i < adapters.length; i++) {
      vm.prank(adapters[i], ZERO_ADDRESS);
      targetCrossChainController.receiveCrossChainMessage(
        _encodedTransaction,
        _originChainId
      );
    }
  }

  function _transferMessage(
    uint256 _targetForkId,
    address _daoAgent,
    address _originCrossChainController,
    address _destinationCrossChainController,
    address _destination,
    uint256 _destinationChainId,
    address[] memory _adapters,
    bytes memory _message
  ) internal returns (uint256) {
    vm.selectFork(ethFork);

    vm.recordLogs();

    // Send DAO motion to the destination executor
    (ExtendedTransaction memory extendedTx) = _sendCrossChainTransactionAsDao(
      _daoAgent,
      _originCrossChainController,
      _destination,
      _destinationChainId,
      _message
    );

    _validateTransactionForwardingSuccess(vm.getRecordedLogs(), 4);

    // Switch to the target fork

    vm.selectFork(_targetForkId);

    vm.recordLogs();
    _receiveDaoCrossChainMessage(
      _destinationCrossChainController,
      _adapters,
      extendedTx.transactionEncoded,
      extendedTx.envelope.originChainId
    );

    // Check that the message was received and passed to the executor
    return _getActionsSetQueued(vm.getRecordedLogs());
  }

  /**
    * @notice Update the mock destination with the specified message
    * @param _targetForkId The target fork ID
    * @param _originCrossChainController The origin cross chain controller
    * @param _destination The destination address
    * @param _destinationChainId The destination chain ID
    * @param _message The message to send
    */
  function _runMockUpdate(
    uint256 _targetForkId,
    address _daoAgent,
    address _originCrossChainController,
    address _destinationCrossChainController,
    address _destination,
    uint256 _destinationChainId,
    address[] memory _adapters,
    address _mockAddress,
    string memory _message
  ) internal {

    uint256 actionId = _transferMessage(
      _targetForkId,
      _daoAgent,
      _originCrossChainController,
      _destinationCrossChainController,
      _destination,
      _destinationChainId,
      _adapters,
      _buildMockUpgradeMotion(_mockAddress, _message)
    );

    // Execute the action received via a.DI
    IExecutorBase executor = IExecutorBase(_destination);

    vm.expectEmit();
    emit TestWorked(_message);

    executor.execute(actionId);

    // Validate that the message was received by the mock destination
    MockDestination mockDestination = MockDestination(_mockAddress);
    assertEq(mockDestination.message(), _message);
  }

  function _buildMockUpgradeMotion(
    address _address,
    string memory _message
  ) internal pure returns (bytes memory) {
    address[] memory addresses = new address[](1);
    addresses[0] = _address;

    uint256[] memory values = new uint256[](1);
    values[0] = uint256(0);

    string[] memory signatures = new string[](1);
    signatures[0] = 'test(string)';

    bytes[] memory calldatas = new bytes[](1);
    calldatas[0] = abi.encode(_message);

    bool[] memory withDelegatecalls = new bool[](1);
    withDelegatecalls[0] = false;

    return abi.encode(addresses, values, signatures, calldatas, withDelegatecalls);
  }
}
