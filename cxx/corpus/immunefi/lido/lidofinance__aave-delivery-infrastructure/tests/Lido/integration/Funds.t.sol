pragma solidity ^0.8.19;

import 'forge-std/console2.sol';
import 'forge-std/Vm.sol';

import {BaseIntegrationTest} from "../BaseIntegrationTest.sol";

import {MockDestination} from "../utils/MockDestination.sol";

import {ICrossChainController} from "../../../src/contracts/interfaces/ICrossChainController.sol";
import {Envelope, EncodedEnvelope} from '../../../src/contracts/libs/EncodingUtils.sol';
import {Errors} from '../../../src/contracts/libs/Errors.sol';

interface IERC20 {
  function transfer(address recipient, uint256 amount) external returns (bool);
  function balanceOf(address account) external view returns (uint256);
}

contract FundsIntegrationTest is BaseIntegrationTest {

  event EnvelopeRegistered(bytes32 indexed envelopeId, Envelope envelope);

  function test_NoFunds_NoEtherOnCrossChainController() public {
    address DAO_AGENT = isRealDaoAgent ? LIDO_DAO_AGENT : LIDO_DAO_AGENT_FAKE;
    address BINANCE_DAO_AGENT = isRealDaoAgent ? crossChainAddresses.bnb.executorProd : crossChainAddresses.bnb.executorMock;

    vm.selectFork(ethFork);
    ICrossChainController crossChainController = ICrossChainController(
      crossChainAddresses.eth.crossChainController
    );

    assertEq(crossChainController.isSenderApproved(DAO_AGENT), true);

    bytes memory message = getMockMessage(address(0), "No funds on CrossChainController");

    // burn all LINK tokens
    uint256 linkBalance = IERC20(ETH_LINK_TOKEN).balanceOf(address(crossChainAddresses.eth.crossChainController));
    vm.prank(crossChainAddresses.eth.crossChainController);
    IERC20(ETH_LINK_TOKEN).transfer(DEAD_ADDRESS, linkBalance);
    linkBalance = IERC20(ETH_LINK_TOKEN).balanceOf(address(crossChainAddresses.eth.crossChainController));

    // Reset the balance of the CrossChainController
    vm.deal(crossChainAddresses.eth.crossChainController, 0);

    assertEq(address(crossChainAddresses.eth.crossChainController).balance, 0);
    assertEq(linkBalance, 0);

    (Envelope memory envelope, EncodedEnvelope memory encodedEnvelope) = _registerEnvelope(
      crossChainController.getCurrentEnvelopeNonce(),
      DAO_AGENT,
      ETHEREUM_CHAIN_ID,
      BINANCE_DAO_AGENT,
      BINANCE_CHAIN_ID,
      message
    );

    // Expect that envelope will register
    vm.expectEmit(true, true, false, false);
    emit EnvelopeRegistered(encodedEnvelope.id, envelope);

    vm.recordLogs();
    vm.prank(DAO_AGENT);
    (bytes32 envelopeId, bytes32 transactionId) = crossChainController.forwardMessage(
      BINANCE_CHAIN_ID,
      BINANCE_DAO_AGENT,
      getGasLimit(),
      message
    );

    // Check that the envelope was registered
    assertEq(envelopeId, encodedEnvelope.id);

    // Check that the transaction failed on all the adapters
    bytes32 signature = keccak256("TransactionForwardingAttempted(bytes32,bytes32,bytes,uint256,address,address,bool,bytes)");
    Vm.Log[] memory entries = vm.getRecordedLogs();

    uint256 count = 0;
    for (uint256 i = 0; i < entries.length; i++) {
      if (entries[i].topics[0] == signature) {
        assertTrue(entries[i].topics[3] == bytes32(0), "Transaction should not be successful");
        count++;
      }
    }

    assertEq(count, 4); // 4 adapters should fail

    // Add funds to the CrossChainController
    vm.deal(crossChainAddresses.eth.crossChainController, 100 ether);

    vm.prank(DAO_AGENT);
    (bytes32 newEnvelopeTransactionId) = crossChainController.retryEnvelope(envelope, getGasLimit());
    assertNotEq(newEnvelopeTransactionId, transactionId);

    // Retry the transaction
    vm.prank(DAO_AGENT);
    (bytes32 newTransactionId) = crossChainController.retryEnvelope(envelope, getGasLimit());

    // Check that the transaction is new
    assertNotEq(newTransactionId, transactionId);
  }

  function test_NoFunds_NoLinkTokensOnCrossChainController() public {
    address DAO_AGENT = isRealDaoAgent ? LIDO_DAO_AGENT : LIDO_DAO_AGENT_FAKE;
    address BINANCE_DAO_AGENT = isRealDaoAgent ? crossChainAddresses.bnb.executorProd : crossChainAddresses.bnb.executorMock;

    ICrossChainController crossChainController = ICrossChainController(
      crossChainAddresses.eth.crossChainController
    );

    bytes memory message = getMockMessage(address(0), "No LINK tokens on CrossChainController");

    // burn all LINK tokens
    uint256 linkBalance = IERC20(ETH_LINK_TOKEN).balanceOf(address(crossChainAddresses.eth.crossChainController));
    vm.prank(crossChainAddresses.eth.crossChainController);
    IERC20(ETH_LINK_TOKEN).transfer(DEAD_ADDRESS, linkBalance);
    linkBalance = IERC20(ETH_LINK_TOKEN).balanceOf(address(crossChainAddresses.eth.crossChainController));

    assertEq(linkBalance, 0);

    vm.recordLogs();
    vm.prank(DAO_AGENT);
    crossChainController.forwardMessage(
      BINANCE_CHAIN_ID,
      BINANCE_DAO_AGENT,
      getGasLimit(),
      message
    );

    // Check that the transaction failed on all the adapters
    bytes32 signature = keccak256("TransactionForwardingAttempted(bytes32,bytes32,bytes,uint256,address,address,bool,bytes)");
    Vm.Log[] memory entries = vm.getRecordedLogs();

    uint256 count = 0;
    for (uint256 i = 0; i < entries.length; i++) {
      if (entries[i].topics[0] == signature && entries[i].topics[3] == bytes32(0)) {
        count++;
      }
    }

    assertEq(count, 1); // CCIP adapter should fail because of no LINK token funds
  }

  function test_NoFunds_FundsOnCrossChainControllerAreOK() public {
    address DAO_AGENT = isRealDaoAgent ? LIDO_DAO_AGENT : LIDO_DAO_AGENT_FAKE;
    address BINANCE_DAO_AGENT = isRealDaoAgent ? crossChainAddresses.bnb.executorProd : crossChainAddresses.bnb.executorMock;

    ICrossChainController crossChainController = ICrossChainController(crossChainAddresses.eth.crossChainController);
    transferLinkTokens(crossChainAddresses.eth.crossChainController);

    bytes memory message = getMockMessage(address(0), "Funds are in place on CrossChainController");

    vm.recordLogs();
    vm.prank(DAO_AGENT);
    crossChainController.forwardMessage(
      BINANCE_CHAIN_ID,
      BINANCE_DAO_AGENT,
      getGasLimit(),
      message
    );

    // Check that the transaction failed on all the adapters
    bytes32 signature = keccak256("TransactionForwardingAttempted(bytes32,bytes32,bytes,uint256,address,address,bool,bytes)");
    Vm.Log[] memory entries = vm.getRecordedLogs();

    uint256 count = 0;
    for (uint256 i = 0; i < entries.length; i++) {
      if (entries[i].topics[0] == signature && entries[i].topics[3] == bytes32(0)) {
        count++;
      }
    }

    assertEq(count, 0); // No adapter should fail
  }

  // Helpers

  function getMockMessage(
    address _address,
    string memory _message
  ) public pure returns (bytes memory) {
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
