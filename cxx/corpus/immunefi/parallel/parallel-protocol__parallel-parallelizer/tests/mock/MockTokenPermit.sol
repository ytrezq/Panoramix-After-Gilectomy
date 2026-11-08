// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract MockTokenPermit is ERC20Permit {
  using SafeERC20 for IERC20;

  event Minting(address indexed _to, address indexed _minter, uint256 _amount);

  event Burning(address indexed _from, address indexed _burner, uint256 _amount);

  event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);
  event AuthorizationCanceled(address indexed authorizer, bytes32 indexed nonce);

  // EIP-3009 type hashes
  bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
    0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267;
  bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH =
    0xd099cc98ef71107a616c4f0f941f04c322d8e254fe26b3c6668db87aae413de8;
  bytes32 public constant CANCEL_AUTHORIZATION_TYPEHASH =
    0x158b0a9edf7a828aad02f63cd515c68ef2f50ba807396f6d12842833a1597429;

  mapping(address => mapping(bytes32 => bool)) private _authorizationStates;

  uint8 internal _decimal;
  mapping(address => bool) public minters;
  address public treasury;
  uint256 public fees;

  bool public reverts;

  constructor(string memory name_, string memory symbol_, uint8 decimal_) ERC20Permit(name_) ERC20(name_, symbol_) {
    _decimal = decimal_;
  }

  function decimals() public view override returns (uint8) {
    return _decimal;
  }

  function mint(address account, uint256 amount) external {
    _mint(account, amount);
    emit Minting(account, msg.sender, amount);
  }

  function burn(address account, uint256 amount) public {
    _burn(account, amount);
    emit Burning(account, msg.sender, amount);
  }

  function setAllowance(address from, address to) public {
    _approve(from, to, type(uint256).max);
  }

  function burnSelf(uint256 amount, address account) public {
    _burn(account, amount);
    emit Burning(account, msg.sender, amount);
  }

  function addMinter(address minter) public {
    minters[minter] = true;
  }

  function removeMinter(address minter) public {
    minters[minter] = false;
  }

  function setTreasury(address _treasury) public {
    treasury = _treasury;
  }

  function setFees(uint256 _fees) public {
    fees = _fees;
  }

  function recoverERC20(IERC20 token, address to, uint256 amount) external {
    token.safeTransfer(to, amount);
  }

  function swapIn(address bridgeToken, uint256 amount, address to) external returns (uint256) {
    require(!reverts);

    IERC20(bridgeToken).safeTransferFrom(msg.sender, address(this), amount);
    uint256 canonicalOut = amount;
    canonicalOut -= (canonicalOut * fees) / 10 ** 9;
    _mint(to, canonicalOut);
    return canonicalOut;
  }

  function swapOut(address bridgeToken, uint256 amount, address to) external returns (uint256) {
    require(!reverts);
    _burn(msg.sender, amount);
    uint256 bridgeOut = amount;
    bridgeOut -= (bridgeOut * fees) / 10 ** 9;
    IERC20(bridgeToken).safeTransfer(to, bridgeOut);
    return bridgeOut;
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    EIP-3009
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function authorizationState(address authorizer, bytes32 nonce) external view returns (bool) {
    return _authorizationStates[authorizer][nonce];
  }

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
  {
    _requireValidAuthorization(from, nonce, validAfter, validBefore);
    _requireValidSignature(
      from,
      keccak256(abi.encode(TRANSFER_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)),
      abi.encodePacked(r, s, v)
    );
    _authorizationStates[from][nonce] = true;
    emit AuthorizationUsed(from, nonce);
    _transfer(from, to, value);
  }

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
  {
    _receiveWithAuthorization(from, to, value, validAfter, validBefore, nonce, abi.encodePacked(r, s, v));
  }

  function receiveWithAuthorization(
    address from,
    address to,
    uint256 value,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    bytes calldata signature
  )
    external
  {
    _receiveWithAuthorization(from, to, value, validAfter, validBefore, nonce, signature);
  }

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
    require(to == msg.sender, "caller must be the payee");
    _requireValidAuthorization(from, nonce, validAfter, validBefore);
    _requireValidSignature(
      from,
      keccak256(abi.encode(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)),
      signature
    );
    _authorizationStates[from][nonce] = true;
    emit AuthorizationUsed(from, nonce);
    _transfer(from, to, value);
  }

  function cancelAuthorization(address authorizer, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external {
    require(!_authorizationStates[authorizer][nonce], "authorization is used");
    _requireValidSignature(
      authorizer,
      keccak256(abi.encode(CANCEL_AUTHORIZATION_TYPEHASH, authorizer, nonce)),
      abi.encodePacked(r, s, v)
    );
    _authorizationStates[authorizer][nonce] = true;
    emit AuthorizationCanceled(authorizer, nonce);
  }

  function _requireValidAuthorization(address authorizer, bytes32 nonce, uint256 validAfter, uint256 validBefore)
    private
    view
  {
    require(block.timestamp > validAfter, "authorization is not yet valid");
    require(block.timestamp < validBefore, "authorization is expired");
    require(!_authorizationStates[authorizer][nonce], "authorization is used");
  }

  function _requireValidSignature(address signer, bytes32 dataHash, bytes memory signature) private view {
    require(
      SignatureChecker.isValidSignatureNow(
        signer, MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR(), dataHash), signature
      ),
      "invalid signature"
    );
  }

  // solhint-disable-next-line func-name-mixedcase
  function DOMAIN_SEPARATOR() public view override returns (bytes32) {
    return _domainSeparatorV4();
  }
}
