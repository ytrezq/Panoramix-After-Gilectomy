pragma solidity ^0.8.19;

import 'forge-std/console2.sol';
import 'forge-std/Vm.sol';

import {Envelope, EncodedEnvelope, Transaction, EncodedTransaction} from '../../src/contracts/libs/EncodingUtils.sol';

import "../BaseTest.sol";

interface Transferable {
  function transfer(address recipient, uint256 amount) external returns (bool);
}

contract BaseTestHelpers is BaseTest {
  uint256 internal immutable ETHEREUM_CHAIN_ID = 1;
  uint256 internal immutable BINANCE_CHAIN_ID = 56;

  address internal immutable ETH_LINK_TOKEN = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
  address internal immutable ETH_LINK_TOKEN_HOLDER = 0x5Eab1966D5F61E52C22D0279F06f175e36A7181E;

  address internal constant LIDO_DAO_AGENT = 0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c;
  address internal constant LIDO_DAO_AGENT_FAKE = 0x184d39300f2fA4419d04998e9C58Cb5De586d879;
  address internal constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
  address internal constant ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;

  function getGasLimit() public view virtual returns (uint256) {
    return 300_000;
  }

  /**
    * @notice Transfer 100 LINK tokens to the specified address
    * @param _to The address to transfer the LINK tokens to
    */
  function transferLinkTokens(
    address _to
  ) public {
    vm.prank(ETH_LINK_TOKEN_HOLDER, ZERO_ADDRESS);
    Transferable(ETH_LINK_TOKEN).transfer(_to, 100e18);
  }

  /**
    * @notice Generate an envelope for a.DI transaction
    *
    * @param _nonce The nonce of the envelope
    * @param _origin The origin address of the envelope
    * @param _originChainId The origin chain ID of the envelope
    * @param _destination The destination address of the envelope
    * @param _destinationChainId The destination chain ID of the envelope
    * @param _message The message of the envelope
    * @return envelope The envelope object
    * @return encodedEnvelope The encoded envelope object
    */
  function _registerEnvelope(
    uint256 _nonce,
    address _origin,
    uint256 _originChainId,
    address _destination,
    uint256 _destinationChainId,
    bytes memory _message
  ) internal pure returns (Envelope memory, EncodedEnvelope memory) {
    Envelope memory envelope = Envelope({
      nonce: _nonce,
      origin: _origin,
      destination: _destination,
      originChainId: _originChainId,
      destinationChainId: _destinationChainId,
      message: _message
    });

    EncodedEnvelope memory encodedEnvelope = envelope.encode();

    return (envelope, encodedEnvelope);
  }

  /**
    * @notice Generate a transaction to send via a.DI
    *
    * @param _envelopeNonce The nonce of the envelope
    * @param _transactionNonce The nonce of the transaction
    * @param _origin The origin address of the envelope
    * @param _originChainId The origin chain ID of the envelope
    * @param _destination The destination address of the envelope
    * @param _destinationChainId The destination chain ID of the envelope
    * @param _message The message of the envelope
    * @return extendedTx The extended transaction object
    */
  function _registerExtendedTransaction(
    uint256 _envelopeNonce,
    uint256 _transactionNonce,
    address _origin,
    uint256 _originChainId,
    address _destination,
    uint256 _destinationChainId,
    bytes memory _message
  ) internal pure returns (ExtendedTransaction memory) {
    ExtendedTransaction memory extendedTx;

    extendedTx.envelope = Envelope({
      nonce: _envelopeNonce,
      origin: _origin,
      destination: _destination,
      originChainId: _originChainId,
      destinationChainId: _destinationChainId,
      message: _message
    });
    EncodedEnvelope memory encodedEnvelope = extendedTx.envelope.encode();
    extendedTx.envelopeEncoded = encodedEnvelope.data;
    extendedTx.envelopeId = encodedEnvelope.id;

    extendedTx.transaction = Transaction({
      nonce: _transactionNonce,
      encodedEnvelope: extendedTx.envelopeEncoded
    });
    EncodedTransaction memory encodedTransaction = extendedTx.transaction.encode();
    extendedTx.transactionEncoded = encodedTransaction.data;
    extendedTx.transactionId = encodedTransaction.id;

    return extendedTx;
  }

  /**
    * @notice Validates that the transaction forwarding was attempted
    *
    * @param _entries The logs to validate
    * @param _expectedCount The expected count of transaction forwarding attempts
    */
  function _validateTransactionForwardingSuccess(
    Vm.Log[] memory _entries,
    uint256 _expectedCount
  ) internal {
    bytes32 signature = keccak256("TransactionForwardingAttempted(bytes32,bytes32,bytes,uint256,address,address,bool,bytes)");

    uint256 count = 0;
    for (uint256 i = 0; i < _entries.length; i++) {
      if (_entries[i].topics[0] == signature && _entries[i].topics[3] == bytes32(uint(1))) {
        count++;
      }
    }

    assertGe(count, _expectedCount); // expected count of adapters should succeed
  }

  /**
    * @notice Validates that the action was queued
    *
    * @param _entries The logs to validate
    * @return actionId The ID of the action that was queued
    */
  function _getActionsSetQueued(
    Vm.Log[] memory _entries
  ) internal returns (uint256) {
    bytes32 signature = keccak256("ActionsSetQueued(uint256,address[],uint256[],string[],bytes[],bool[],uint256)");

    uint256 actionId;
    uint256 count = 0;
    for (uint256 i = 0; i < _entries.length; i++) {
      if (_entries[i].topics[0] == signature) {
        count++;
        actionId = uint256(_entries[i].topics[1]);
      }
    }

    assertEq(count, 1); // action should be queued

    return actionId;
  }
}
