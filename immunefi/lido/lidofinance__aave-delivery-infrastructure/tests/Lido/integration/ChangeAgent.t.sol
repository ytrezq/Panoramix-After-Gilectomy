pragma solidity ^0.8.19;

import 'forge-std/console2.sol';
import 'forge-std/Vm.sol';

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Ownable} from "solidity-utils/contracts/oz-common/Ownable.sol";
import {OwnableWithGuardian} from "solidity-utils/contracts/access-control/OwnableWithGuardian.sol";
import {IRescuable} from "solidity-utils/contracts/utils/interfaces/IRescuable.sol";

import {BaseIntegrationTest} from "../BaseIntegrationTest.sol";

import {CrossChainController} from "../../../src/contracts/CrossChainController.sol";
import {ICrossChainController} from "../../../src/contracts/interfaces/ICrossChainController.sol";
import {ICrossChainReceiver} from "../../../src/contracts/interfaces/ICrossChainReceiver.sol";
import {ICrossChainForwarder} from "../../../src/contracts/interfaces/ICrossChainForwarder.sol";

import {Envelope, EncodedEnvelope} from '../../../src/contracts/libs/EncodingUtils.sol';
import {Errors} from "../../../src/contracts/libs/Errors.sol";

import {IExecutorBase} from "../../../src/Lido/contracts/interfaces/IExecutorBase.sol";
import {CrossChainExecutor} from "../../../src/Lido/contracts/CrossChainExecutor.sol";

import {MockDestination} from "../utils/MockDestination.sol";

contract ChangeAgentIntegrationTest is BaseIntegrationTest {
  address public BINANCE_DAO_AGENT;

  event EnvelopeRegistered(bytes32 indexed envelopeId, Envelope envelope);
  event ConfirmationsUpdated(uint8 newConfirmations, uint256 indexed chainId);

  string private messageToMock = "This is a message to mock";

  uint8 private constant newConfirmations = 2;

  function setUp() override public {
    super.setUp();

    vm.selectFork(ethFork);
    transferLinkTokens(ethCCCAddress);

    BINANCE_DAO_AGENT = isRealDaoAgent ? crossChainAddresses.bnb.executorProd : crossChainAddresses.bnb.executorMock;
  }

  function test_ChangeAgent_OnBinance() public {
    address AGENT_1 = isRealDaoAgent ? LIDO_DAO_AGENT : LIDO_DAO_AGENT_FAKE;
    address AGENT_2 = isRealDaoAgent ? LIDO_DAO_AGENT_FAKE : LIDO_DAO_AGENT;

    vm.selectFork(bnbFork);
    address oldMockDestination = address(new MockDestination(BINANCE_DAO_AGENT));
    (address newBinanceExecutor, address newMockDestination) = _deployNewBinanceExecutorAndMock(AGENT_2);

    vm.selectFork(ethFork);
    _runMockUpdate(
      bnbFork,
      AGENT_1, // DAO Agent 1 - the one after deploy
      ethCCCAddress,
      crossChainAddresses.bnb.crossChainController,
      BINANCE_DAO_AGENT,
      BINANCE_CHAIN_ID,
      bnbAdapters,
      oldMockDestination,
      messageToMock
    );

    _runUnauthorizedUpdate(
      AGENT_2, // DAO Agent 2 - the real one
      ethCCCAddress,
      BINANCE_DAO_AGENT,
      BINANCE_CHAIN_ID,
      oldMockDestination,
      messageToMock
    );

    _transferOwnershipOnBinance(AGENT_1, newBinanceExecutor);

    _transferOwnershipOnEthereum(AGENT_1, AGENT_2);

    _runMockUpdate(
      bnbFork,
      AGENT_2,
      ethCCCAddress,
      crossChainAddresses.bnb.crossChainController,
      newBinanceExecutor,
      BINANCE_CHAIN_ID,
      bnbAdapters,
      newMockDestination,
      messageToMock
    );

    // Validate that old sender is not approved
    _runUnauthorizedUpdate(
      AGENT_1,
      ethCCCAddress,
      newBinanceExecutor,
      BINANCE_CHAIN_ID,
      newMockDestination,
      messageToMock
    );

    // Validate that old sender can't utilize the old executor
    _runUnauthorizedUpdate(
      AGENT_1,
      ethCCCAddress,
      BINANCE_DAO_AGENT,
      BINANCE_CHAIN_ID,
      oldMockDestination,
      messageToMock
    );
  }

  function _deployNewBinanceExecutorAndMock(
    address _newDaoAgent
  ) internal returns (address upgradedExecutorBnbAddress, address upgradedMockDestination) {
    vm.selectFork(bnbFork);

    // Deploy new BSC side executor for the new DAO agent
    upgradedExecutorBnbAddress = address(new CrossChainExecutor(
      crossChainAddresses.bnb.crossChainController,
      _newDaoAgent,
      ETHEREUM_CHAIN_ID,
      0,          // delay
      86400,      // gracePeriod
      0,          // minimumDelay
      1,          // maximumDelay
      address(0)  // guardian
    ));

    upgradedMockDestination = address(new MockDestination(upgradedExecutorBnbAddress));

    return (upgradedExecutorBnbAddress, upgradedMockDestination);
  }

  /**
    * @notice Run a an a.DI setup upgrade to pass ownership to the new DAO agent
    */
  function _transferOwnershipOnBinance(
    address _daoAgent,
    address _newExecutorBnbAddress
  ) internal {
    bytes memory motion = _buildBnbOwnershipTransferMotion(_newExecutorBnbAddress);

    uint256 actionId = _transferMessage(
      bnbFork,
      _daoAgent,
      ethCCCAddress,
      crossChainAddresses.bnb.crossChainController,
      BINANCE_DAO_AGENT,
      BINANCE_CHAIN_ID,
      bnbAdapters,
      motion
    );

    vm.selectFork(bnbFork);

    // Validate that the ProxyAdmin owner is the original executor
    address proxyAdminOwner = Ownable(crossChainAddresses.bnb.proxyAdmin).owner();
    assertEq(proxyAdminOwner, BINANCE_DAO_AGENT, "ProxyAdmin owner should be set to original executor");

    address cccOwner = Ownable(crossChainAddresses.bnb.crossChainController).owner();
    assertEq(cccOwner, BINANCE_DAO_AGENT, "CrossChainController owner should be set to original executor");

    // Run the motion
    IExecutorBase executor = IExecutorBase(BINANCE_DAO_AGENT);
    executor.execute(actionId);

    // Validate that the ownership was transferred
    ProxyAdmin proxyAdminContract = ProxyAdmin(crossChainAddresses.bnb.proxyAdmin);
    ITransparentUpgradeableProxy cccProxy = ITransparentUpgradeableProxy(crossChainAddresses.bnb.crossChainController);

    proxyAdminOwner = Ownable(crossChainAddresses.bnb.proxyAdmin).owner();
    address proxyImp = proxyAdminContract.getProxyImplementation(cccProxy);
    address proxyAdminAddress = proxyAdminContract.getProxyAdmin(cccProxy);

    cccOwner = Ownable(crossChainAddresses.bnb.crossChainController).owner();

    assertEq(proxyAdminOwner, _newExecutorBnbAddress, "ProxyAdmin owner should be updated new executor");
    assertEq(cccOwner, _newExecutorBnbAddress, "CrossChainController owner should be updated new executor");
    assertEq(proxyAdminAddress, crossChainAddresses.bnb.proxyAdmin, "ProxyAdmin for CrossChainController should be ProxyAdmin");
    assertEq(proxyImp, crossChainAddresses.bnb.crossChainControllerImpl, "CrossChainController implementation should be CrossChainControllerImpl");
  }

  function _transferOwnershipOnEthereum(
    address _daoAgent,
    address _newDaoAgent
  ) internal {
    vm.selectFork(ethFork);
    vm.startPrank(_daoAgent);

    // Swap approved senders
    address[] memory sendersToApprove = new address[](1);
    sendersToApprove[0] = _newDaoAgent;

    ICrossChainForwarder(ethCCCAddress).approveSenders(sendersToApprove);

    address[] memory sendersToRemove = new address[](1);
    sendersToRemove[0] = _daoAgent;

    ICrossChainForwarder(ethCCCAddress).removeSenders(sendersToRemove);

    // Transfer ownership of the CrossChainController and ProxyAdmin to the new DAO agent
    Ownable(crossChainAddresses.eth.crossChainController).transferOwnership(_newDaoAgent);
    Ownable(crossChainAddresses.eth.proxyAdmin).transferOwnership(_newDaoAgent);

    vm.stopPrank();
  }

  /**
    * @notice Run a motion that should revert
    *
    * @param _daoAgent The DAO agent address
    * @param _crossChainController The cross chain controller address
    * @param _executor The executor address
    * @param _chainId The chain ID
    * @param _mockDestination The mock destination address
    * @param _message The message to send
    */
  function _runUnauthorizedUpdate(
    address _daoAgent,
    address _crossChainController,
    address _executor,
    uint256 _chainId,
    address _mockDestination,
    string memory _message
  ) internal {
    vm.selectFork(ethFork);

    ICrossChainController crossChainController = ICrossChainController(_crossChainController);

    assertEq(crossChainController.isSenderApproved(_daoAgent), false);

    vm.expectRevert(bytes(Errors.CALLER_IS_NOT_APPROVED_SENDER));
    crossChainController.forwardMessage(
      _chainId,
      _executor,
      getGasLimit(),
      _buildMockUpgradeMotion(_mockDestination, _message)
    );
  }

  function _buildBnbOwnershipTransferMotion(
    address _newExecutorBnbAddress
  ) internal view returns (bytes memory) {
    address[] memory addresses = new address[](2);
    addresses[0] = crossChainAddresses.bnb.crossChainController;
    addresses[1] = crossChainAddresses.bnb.proxyAdmin;

    uint256[] memory values = new uint256[](2);
    values[0] = uint256(0);
    values[1] = uint256(0);

    string[] memory signatures = new string[](2);
    signatures[0] = 'transferOwnership(address)';
    signatures[1] = 'transferOwnership(address)';

    bytes[] memory calldatas = new bytes[](2);
    calldatas[0] = abi.encode(_newExecutorBnbAddress);
    calldatas[1] = abi.encode(_newExecutorBnbAddress);

    bool[] memory withDelegatecalls = new bool[](2);
    withDelegatecalls[0] = false;
    withDelegatecalls[1] = false;

    return abi.encode(addresses, values, signatures, calldatas, withDelegatecalls);
  }
}
