// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import { IEIP3009 } from "contracts/interfaces/external/IEIP3009.sol";

/// @title EIP3009
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice Abstract implementation of EIP-3009: Transfer With Authorization
/// @dev Supports both EOA (v,r,s) and smart contract wallet (EIP-1271) signatures.
/// The EIP-712 domain separator is computed dynamically from `name()` so no initialization is required.
/// SECURITY: `transferWithAuthorization` has no `msg.sender` restriction and is therefore
/// vulnerable to nonce-burn frontrunning - any observer of the mempool can submit a valid
/// signature ahead of the intended caller, consuming the nonce. Integrations that bind the
/// transfer to follow-on logic (swap, deposit, redeem, etc.) MUST use `receiveWithAuthorization`
/// instead, which enforces `msg.sender == to` and atomically pairs the pull with downstream
/// execution. `transferWithAuthorization` is intended only for direct payouts to a passive
/// recipient.
abstract contract EIP3009 is ERC20Upgradeable, IEIP3009 {
  // keccak256("TransferWithAuthorization(address from,address to,
  //   uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
  bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
    0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267;

  // keccak256("ReceiveWithAuthorization(address from,address to,
  //   uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
  bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH =
    0xd099cc98ef71107a616c4f0f941f04c322d8e254fe26b3c6668db87aae413de8;

  // keccak256("CancelAuthorization(address authorizer,bytes32 nonce)")
  bytes32 public constant CANCEL_AUTHORIZATION_TYPEHASH =
    0x158b0a9edf7a828aad02f63cd515c68ef2f50ba807396f6d12842833a1597429;

  // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
  bytes32 private constant EIP712_DOMAIN_TYPEHASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

  bytes32 private constant VERSION_HASH = keccak256(bytes("1"));

  /// @custom:storage-location erc7201:cooperlabs.storage.EIP3009
  struct EIP3009Storage {
    mapping(address => mapping(bytes32 => bool)) authorizationStates;
  }

  // keccak256(abi.encode(uint256(keccak256("cooperlabs.storage.EIP3009")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant EIP3009StorageLocation = 0x34292e02e92581dc72dd1eedcc379a97daab830d016799aa096bf08b96bd9500;

  function _getEIP3009Storage() private pure returns (EIP3009Storage storage $) {
    assembly {
      $.slot := EIP3009StorageLocation
    }
  }

  event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);
  event AuthorizationCanceled(address indexed authorizer, bytes32 indexed nonce);

  error AuthorizationNotYetValid();
  error AuthorizationExpired();
  error AuthorizationAlreadyUsed(bytes32 nonce);
  error CallerMustBePayee();
  error InvalidSignature();

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function authorizationState(address authorizer, bytes32 nonce) external view returns (bool) {
    return _getEIP3009Storage().authorizationStates[authorizer][nonce];
  }

  // solhint-disable-next-line func-name-mixedcase
  function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
    return _domainSeparator();
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    EXTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /// @inheritdoc IEIP3009
  function transferWithAuthorization(
    address from,
    address to,
    uint256 value,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    uint8 v,
    bytes32 r,
    bytes32 s
  )
    external
    virtual
  {
    _transferWithAuthorization(from, to, value, validAfter, validBefore, nonce, abi.encodePacked(r, s, v));
  }

  /// @inheritdoc IEIP3009
  function transferWithAuthorization(
    address from,
    address to,
    uint256 value,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    bytes memory signature
  )
    external
    virtual
  {
    _transferWithAuthorization(from, to, value, validAfter, validBefore, nonce, signature);
  }

  /// @inheritdoc IEIP3009
  function receiveWithAuthorization(
    address from,
    address to,
    uint256 value,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    uint8 v,
    bytes32 r,
    bytes32 s
  )
    external
    virtual
  {
    _receiveWithAuthorization(from, to, value, validAfter, validBefore, nonce, abi.encodePacked(r, s, v));
  }

  /// @inheritdoc IEIP3009
  function receiveWithAuthorization(
    address from,
    address to,
    uint256 value,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    bytes memory signature
  )
    external
    virtual
  {
    _receiveWithAuthorization(from, to, value, validAfter, validBefore, nonce, signature);
  }

  /// @inheritdoc IEIP3009
  function cancelAuthorization(address authorizer, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external virtual {
    _cancelAuthorization(authorizer, nonce, abi.encodePacked(r, s, v));
  }

  /// @inheritdoc IEIP3009
  function cancelAuthorization(address authorizer, bytes32 nonce, bytes memory signature) external virtual {
    _cancelAuthorization(authorizer, nonce, signature);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    INTERNAL LOGIC
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /// @notice Executes the core logic of an EIP-3009 transfer with authorization.
  /// @dev Inheriting contracts can call this to reuse the EIP-3009 authorization + transfer flow
  /// (for example, a contract that is itself EIP-3009 and wraps an EIP-3009 underlying).
  function _transferWithAuthorization(
    address from,
    address to,
    uint256 value,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    bytes memory signature
  )
    internal
  {
    _requireValidAuthorization(from, nonce, validAfter, validBefore);
    _requireValidSignature(
      from,
      keccak256(abi.encode(TRANSFER_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)),
      signature
    );
    _markAuthorizationAsUsed(from, nonce);
    _transfer(from, to, value);
  }

  /// @notice Executes the core logic of an EIP-3009 receive with authorization.
  /// @dev Enforces that `msg.sender` is the payee (`to`), then runs the standard authorization + transfer flow.
  /// Inheriting contracts can call this to reuse the logic.
  function _receiveWithAuthorization(
    address from,
    address to,
    uint256 value,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    bytes memory signature
  )
    internal
  {
    if (to != msg.sender) revert CallerMustBePayee();
    _requireValidAuthorization(from, nonce, validAfter, validBefore);
    _requireValidSignature(
      from,
      keccak256(abi.encode(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)),
      signature
    );
    _markAuthorizationAsUsed(from, nonce);
    _transfer(from, to, value);
  }

  /// @notice Executes the core logic of an EIP-3009 cancel authorization.
  /// @dev Inheriting contracts can call this to reuse the cancel flow.
  function _cancelAuthorization(address authorizer, bytes32 nonce, bytes memory signature) internal {
    _requireUnusedAuthorization(authorizer, nonce);
    _requireValidSignature(
      authorizer, keccak256(abi.encode(CANCEL_AUTHORIZATION_TYPEHASH, authorizer, nonce)), signature
    );
    _getEIP3009Storage().authorizationStates[authorizer][nonce] = true;
    emit AuthorizationCanceled(authorizer, nonce);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    INTERNAL HELPERS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function _domainSeparator() internal view returns (bytes32) {
    return keccak256(
      abi.encode(EIP712_DOMAIN_TYPEHASH, keccak256(bytes(name())), VERSION_HASH, block.chainid, address(this))
    );
  }

  function _requireValidSignature(address signer, bytes32 dataHash, bytes memory signature) internal view {
    bytes32 digest = MessageHashUtils.toTypedDataHash(_domainSeparator(), dataHash);
    if (!SignatureChecker.isValidSignatureNow(signer, digest, signature)) {
      revert InvalidSignature();
    }
  }

  function _requireValidAuthorization(
    address authorizer,
    bytes32 nonce,
    uint256 validAfter,
    uint256 validBefore
  )
    internal
    view
  {
    if (block.timestamp <= validAfter) revert AuthorizationNotYetValid();
    if (block.timestamp >= validBefore) revert AuthorizationExpired();
    _requireUnusedAuthorization(authorizer, nonce);
  }

  function _requireUnusedAuthorization(address authorizer, bytes32 nonce) internal view {
    if (_getEIP3009Storage().authorizationStates[authorizer][nonce]) revert AuthorizationAlreadyUsed(nonce);
  }

  function _markAuthorizationAsUsed(address authorizer, bytes32 nonce) internal {
    _getEIP3009Storage().authorizationStates[authorizer][nonce] = true;
    emit AuthorizationUsed(authorizer, nonce);
  }
}
