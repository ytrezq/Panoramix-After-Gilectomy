/**
 * SPDX-License-Identifier: BUSL-1.1
 *
 *       ▄▄█████████▄
 *    ╓██▀└ ,╓▄▄▄, '▀██▄
 *   ██▀ ▄██▀▀╙╙▀▀██▄ └██µ           ,,       ,,      ,     ,,,            ,,,
 *  ██ ,██¬ ▄████▄  ▀█▄ ╙█▄      ▄███▀▀███▄   ███▄    ██  ███▀▀▀███▄    ▄███▀▀███,
 * ██  ██ ╒█▀'   ╙█▌ ╙█▌ ██     ▐██      ███  █████,  ██  ██▌    └██▌  ██▌     └██▌
 * ██ ▐█▌ ██      ╟█  █▌ ╟█     ██▌      ▐██  ██ └███ ██  ██▌     ╟██ j██       ╟██
 * ╟█  ██ ╙██    ▄█▀ ▐█▌ ██     ╙██      ██▌  ██   ╙████  ██▌    ▄██▀  ██▌     ,██▀
 *  ██ "██, ╙▀▀███████████⌐      ╙████████▀   ██     ╙██  ███████▀▀     ╙███████▀`
 *   ██▄ ╙▀██▄▄▄▄▄,,,                ¬─                                    '─¬
 *    ╙▀██▄ '╙╙╙▀▀▀▀▀▀▀▀
 *       ╙▀▀██████R⌐
 *
 */
pragma solidity 0.8.33;

import {IERC20} from "contracts/external/openzeppelin/contracts/token/IERC20.sol";
import {
  IERC20Upgradeable
} from "contracts/external/openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {
  IERC20MetadataUpgradeable
} from "contracts/external/openzeppelin/contracts-upgradeable/token/ERC20/IERC20MetadataUpgradeable.sol";
import {
  Initializable
} from "contracts/external/openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import {
  ContextUpgradeable
} from "contracts/external/openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {
  PausableUpgradeable
} from "contracts/external/openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {
  AccessControlEnumerableUpgradeable
} from "contracts/external/openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import {KYCRegistryClientUpgradeable} from "contracts/kyc/KYCRegistryClientUpgradeable.sol";
import {IRWAOracle} from "contracts/rwaOracles/IRWAOracle.sol";

/**
 * @title Interest-bearing ERC20-like token for OUSG.
 *
 * rOUSG balances are dynamic and represent the holder's share of the underlying OUSG
 * controlled by the protocol. To calculate each account's balance, we do
 *
 *   shares[account] * ousgPrice
 *
 * For example, if we assume that we have the following:
 *
 *   ousgPrice = 105 (18 decimals)
 *   rousg.sharesOf(user1) -> 1 (22 decimals)
 *   rousg.sharesOf(user2) -> 4 (22 decimals)
 *   ousg.balanceOf(rousg) -> 5 OUSG (18 decimals)
 *
 * Below would be the balances of the users:
 *
 *   rousg.balanceOf(user1) -> 105 rOUSG (18 decimals)
 *   rousg.balanceOf(user2) -> 420 rOUSG (18 decimals)
 *
 * Since balances of all token holders change when the price of OUSG changes, this
 * token cannot fully implement ERC20 standard: it only emits `Transfer` events
 * upon explicit transfer between holders. In contrast, when total amount of pooled
 * Cash increases, no `Transfer` events are generated: doing so would require emitting
 * an event for each token holder and thus running an unbounded loop.
 *
 */

contract ROUSG is
  Initializable,
  ContextUpgradeable,
  PausableUpgradeable,
  AccessControlEnumerableUpgradeable,
  KYCRegistryClientUpgradeable,
  IERC20Upgradeable,
  IERC20MetadataUpgradeable
{
  /**
   * @dev rOUSG balances are dynamic and are calculated based on the accounts' shares (OUSG)
   * and the the price of OUSG. Account shares aren't
   * normalized, so the contract also stores the sum of all shares to calculate
   * each account's token balance which equals to:
   *
   *   shares[account] * ousgPrice
   */
  mapping(address => uint256) private shares;

  /// @dev Allowances are nominated in tokens, not token shares.
  mapping(address => mapping(address => uint256)) private allowances;

  // Total shares in existence
  uint256 public totalShares;

  // Address of the oracle that provides the `ousgPrice`
  IRWAOracle public oracle;

  // Address of the OUSG token
  IERC20 public ousg;

  // Used to scale up ousg amount -> shares
  uint256 public constant OUSG_TO_ROUSG_SHARES_MULTIPLIER = 10_000;

  // Name of the token
  string internal _name;

  // Symbol of the token
  string internal _symbol;

  // Error when redeeming shares < `OUSG_TO_ROUSG_SHARES_MULTIPLIER`
  error UnwrapTooSmall();

  // Error when setting the oracle address to zero
  error CannotSetToZeroAddress();

  /// @dev Role based access control roles
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
  bytes32 public constant BURNER_ROLE = keccak256("BURN_ROLE");
  bytes32 public constant CONFIGURER_ROLE = keccak256("CONFIGURER_ROLE");

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address _kycRegistry,
    uint256 requirementGroup,
    address _ousg,
    address guardian,
    address _oracle
  ) public virtual initializer {
    __rOUSG_init(_kycRegistry, requirementGroup, _ousg, guardian, _oracle);
  }

  function __rOUSG_init(
    address _kycRegistry,
    uint256 requirementGroup,
    address _ousg,
    address guardian,
    address _oracle
  ) internal onlyInitializing {
    __rOUSG_init_unchained(_kycRegistry, requirementGroup, _ousg, guardian, _oracle);
  }

  function __rOUSG_init_unchained(
    address _kycRegistry,
    uint256 _requirementGroup,
    address _ousg,
    address guardian,
    address _oracle
  ) internal onlyInitializing {
    __KYCRegistryClientInitializable_init(_kycRegistry, _requirementGroup);
    ousg = IERC20(_ousg);
    oracle = IRWAOracle(_oracle);
    _grantRole(DEFAULT_ADMIN_ROLE, guardian);
    _grantRole(PAUSER_ROLE, guardian);
    _grantRole(BURNER_ROLE, guardian);
    _grantRole(CONFIGURER_ROLE, guardian);
    _name = "Ondo Short-Term U.S. Government Bond Fund (Rebasing)";
    _symbol = "rOUSG";
  }

  /**
   * @notice Emitted when the name is set
   *
   * @param oldName The old name of the token
   * @param newName The new name of the token
   */
  event NameSet(string oldName, string newName);

  /**
   * @notice Emitted when the symbol is set
   *
   * @param oldSymbol The old symbol of the token
   * @param newSymbol The new symbol of the token
   */

  event SymbolSet(string oldSymbol, string newSymbol);
  /**
   * @notice An executed shares transfer from `sender` to `recipient`.
   *
   * @dev emitted in pair with an ERC20-defined `Transfer` event.
   */
  event TransferShares(address indexed from, address indexed to, uint256 sharesValue);

  /**
   * @notice Emitted when the oracle address is set
   *
   * @param oldOracle The address of the old oracle
   * @param newOracle The address of the new oracle
   */
  event OracleSet(address indexed oldOracle, address indexed newOracle);

  /**
   * @return the name of the token.
   */
  function name() public view returns (string memory) {
    return _name;
  }

  /**
   * @return the symbol of the token, usually a shorter version of the
   * name.
   */
  function symbol() public view returns (string memory) {
    return _symbol;
  }

  /**
   * @return the number of decimals for getting user representation of a token amount.
   */
  function decimals() public pure returns (uint8) {
    return 18;
  }

  /**
   * @return the amount of tokens in existence.
   */
  function totalSupply() public view returns (uint256) {
    return (totalShares * getOUSGPrice()) / (1e18 * OUSG_TO_ROUSG_SHARES_MULTIPLIER);
  }

  /**
   * @return the amount of tokens owned by the `_account`.
   *
   * @dev Balances are dynamic and equal the `_account`'s OUSG shares multiplied
   *      by the price of OUSG
   */
  function balanceOf(address _account) public view returns (uint256) {
    return (_sharesOf(_account) * getOUSGPrice()) / (1e18 * OUSG_TO_ROUSG_SHARES_MULTIPLIER);
  }

  /**
   * @notice Moves `_amount` tokens from the caller's account to the `_recipient` account.
   *
   * @return a boolean value indicating whether the operation succeeded.
   * Emits a `Transfer` event.
   * Emits a `TransferShares` event.
   *
   * Requirements:
   *
   * - `_recipient` cannot be the zero address.
   * - the caller must have a balance of at least `_amount`.
   * - the contract must not be paused.
   *
   * @dev The `_amount` argument is the amount of tokens, not shares.
   */
  function transfer(address _recipient, uint256 _amount) public returns (bool) {
    _transfer(msg.sender, _recipient, _amount);
    return true;
  }

  /**
   * @return the remaining number of tokens that `_spender` is allowed to spend
   * on behalf of `_owner` through `transferFrom`. This is zero by default.
   *
   * @dev This value changes when `approve` or `transferFrom` is called.
   */
  function allowance(address _owner, address _spender) public view returns (uint256) {
    return allowances[_owner][_spender];
  }

  /**
   * @notice Sets `_amount` as the allowance of `_spender` over the caller's tokens.
   *
   * @return a boolean value indicating whether the operation succeeded.
   * Emits an `Approval` event.
   *
   * Requirements:
   *
   * - `_spender` cannot be the zero address.
   * - the contract must not be paused.
   *
   * @dev The `_amount` argument is the amount of tokens, not shares.
   */
  function approve(address _spender, uint256 _amount) public returns (bool) {
    _approve(msg.sender, _spender, _amount);
    return true;
  }

  /**
   * @notice Moves `_amount` tokens from `_sender` to `_recipient` using the
   * allowance mechanism. `_amount` is then deducted from the caller's
   * allowance.
   *
   * @return a boolean value indicating whether the operation succeeded.
   *
   * Emits a `Transfer` event.
   * Emits a `TransferShares` event.
   * Emits an `Approval` event indicating the updated allowance.
   *
   * Requirements:
   *
   * - `_sender` and `_recipient` cannot be the zero addresses.
   * - `_sender` must have a balance of at least `_amount`.
   * - the caller must have allowance for `_sender`'s tokens of at least `_amount`.
   * - the contract must not be paused.
   *
   * @dev The `_amount` argument is the amount of tokens, not shares.
   */
  function transferFrom(address _sender, address _recipient, uint256 _amount)
    public
    returns (bool)
  {
    uint256 currentAllowance = allowances[_sender][msg.sender];
    require(currentAllowance >= _amount, "TRANSFER_AMOUNT_EXCEEDS_ALLOWANCE");

    _transfer(_sender, _recipient, _amount);
    _approve(_sender, msg.sender, currentAllowance - _amount);
    return true;
  }

  /**
   * @notice Atomically increases the allowance granted to `_spender` by the caller by `_addedValue`.
   *
   * This is an alternative to `approve` that can be used as a mitigation for
   * problems described in:
   * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol#L42
   * Emits an `Approval` event indicating the updated allowance.
   *
   * Requirements:
   *
   * - `_spender` cannot be the the zero address.
   * - the contract must not be paused.
   */
  function increaseAllowance(address _spender, uint256 _addedValue) public returns (bool) {
    _approve(msg.sender, _spender, allowances[msg.sender][_spender] + _addedValue);
    return true;
  }

  /**
   * @notice Atomically decreases the allowance granted to `_spender` by the caller by `_subtractedValue`.
   *
   * This is an alternative to `approve` that can be used as a mitigation for
   * problems described in:
   * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol#L42
   * Emits an `Approval` event indicating the updated allowance.
   *
   * Requirements:
   *
   * - `_spender` cannot be the zero address.
   * - `_spender` must have allowance for the caller of at least `_subtractedValue`.
   * - the contract must not be paused.
   */
  function decreaseAllowance(address _spender, uint256 _subtractedValue) public returns (bool) {
    uint256 currentAllowance = allowances[msg.sender][_spender];
    require(currentAllowance >= _subtractedValue, "DECREASED_ALLOWANCE_BELOW_ZERO");
    _approve(msg.sender, _spender, currentAllowance - _subtractedValue);
    return true;
  }

  /**
   * @return the amount of shares owned by `_account`.
   *
   * @dev This is the equivalent to the amount of OUSG wrapped by `_account`.
   */
  function sharesOf(address _account) public view returns (uint256) {
    return _sharesOf(_account);
  }

  /**
   * @return the amount of shares that corresponds to `_rOUSGAmount` of rOUSG
   */
  function getSharesByROUSG(uint256 _rOUSGAmount) public view returns (uint256) {
    return (_rOUSGAmount * 1e18 * OUSG_TO_ROUSG_SHARES_MULTIPLIER) / getOUSGPrice();
  }

  /**
   * @return the amount of rOUSG that corresponds to `_shares` of OUSG.
   */
  function getROUSGByShares(uint256 _shares) public view returns (uint256) {
    return (_shares * getOUSGPrice()) / (1e18 * OUSG_TO_ROUSG_SHARES_MULTIPLIER);
  }

  function getOUSGPrice() public view returns (uint256 price) {
    (price,) = oracle.getPriceData();
  }

  /**
   * @notice Moves `_sharesAmount` token shares from the caller's account to the `_recipient` account.
   *
   * @return amount of transferred tokens.
   * Emits a `TransferShares` event.
   * Emits a `Transfer` event.
   *
   * Requirements:
   *
   * - `_recipient` cannot be the zero address.
   * - the caller must have at least `_sharesAmount` shares.
   * - the contract must not be paused.
   *
   * @dev The `_sharesAmount` argument is the amount of shares, not tokens.
   */
  function transferShares(address _recipient, uint256 _sharesAmount) public returns (uint256) {
    _transferShares(msg.sender, _recipient, _sharesAmount);
    emit TransferShares(msg.sender, _recipient, _sharesAmount);
    uint256 tokensAmount = getROUSGByShares(_sharesAmount);
    emit Transfer(msg.sender, _recipient, tokensAmount);
    return tokensAmount;
  }

  /**
   * @notice Function called by users to wrap their OUSG tokens
   *
   * @param _OUSGAmount The amount of OUSG Tokens to wrap
   *
   * @dev KYC checks implicit in OUSG Transfer
   */
  function wrap(uint256 _OUSGAmount) external whenNotPaused {
    require(_OUSGAmount > 0, "rOUSG: can't wrap zero OUSG tokens");
    uint256 ousgSharesAmount = _OUSGAmount * OUSG_TO_ROUSG_SHARES_MULTIPLIER;
    _mintShares(msg.sender, ousgSharesAmount);
    // forge-lint: disable-next-line(erc20-unchecked-transfer)
    ousg.transferFrom(msg.sender, address(this), _OUSGAmount);
    emit Transfer(address(0), msg.sender, getROUSGByShares(ousgSharesAmount));
    emit TransferShares(address(0), msg.sender, ousgSharesAmount);
  }

  /**
   * @notice Function called by users to unwrap their rOUSG tokens by rOUSG amount
   *
   * @param _rOUSGAmount The amount of rOUSG to unwrap
   *
   * @dev KYC checks implicit in OUSG Transfer
   */
  function unwrap(uint256 _rOUSGAmount) external whenNotPaused {
    require(_rOUSGAmount > 0, "rOUSG: can't unwrap zero rOUSG tokens");
    uint256 ousgSharesAmount = getSharesByROUSG(_rOUSGAmount);
    if (ousgSharesAmount < OUSG_TO_ROUSG_SHARES_MULTIPLIER) {
      revert UnwrapTooSmall();
    }
    _burnShares(msg.sender, ousgSharesAmount);
    // forge-lint: disable-next-line(erc20-unchecked-transfer)
    ousg.transfer(msg.sender, ousgSharesAmount / OUSG_TO_ROUSG_SHARES_MULTIPLIER);
    emit Transfer(msg.sender, address(0), _rOUSGAmount);
    emit TransferShares(msg.sender, address(0), ousgSharesAmount);
  }

  /**
   * @notice Function called by users to unwrap their rOUSG tokens by shares
   *
   * @param _sharesAmount The amount of shares to transfer
   *
   * @dev KYC checks implicit in OUSG Transfer
   * @dev This is a more precise unwrap, as it avoids the division by price when converting rOUSG to shares
   */
  function unwrapShares(uint256 _sharesAmount) external whenNotPaused {
    if (_sharesAmount < OUSG_TO_ROUSG_SHARES_MULTIPLIER) {
      revert UnwrapTooSmall();
    }

    uint256 rOUSGAmount = getROUSGByShares(_sharesAmount);

    _burnShares(msg.sender, _sharesAmount);
    // forge-lint: disable-next-line(erc20-unchecked-transfer)
    ousg.transfer(msg.sender, _sharesAmount / OUSG_TO_ROUSG_SHARES_MULTIPLIER);
    emit Transfer(msg.sender, address(0), rOUSGAmount);
    emit TransferShares(msg.sender, address(0), _sharesAmount);
  }

  /**
   * @notice Moves `_amount` tokens from `_sender` to `_recipient`.
   * Emits a `Transfer` event.
   * Emits a `TransferShares` event.
   */
  function _transfer(address _sender, address _recipient, uint256 _amount) internal {
    uint256 _sharesToTransfer = getSharesByROUSG(_amount);
    _transferShares(_sender, _recipient, _sharesToTransfer);
    emit Transfer(_sender, _recipient, _amount);
    emit TransferShares(_sender, _recipient, _sharesToTransfer);
  }

  /**
   * @notice Sets `_amount` as the allowance of `_spender` over the `_owner` s tokens.
   *
   * Emits an `Approval` event.
   *
   * Requirements:
   *
   * - `_owner` cannot be the zero address.
   * - `_spender` cannot be the zero address.
   * - the contract must not be paused.
   */
  function _approve(address _owner, address _spender, uint256 _amount) internal whenNotPaused {
    require(_owner != address(0), "APPROVE_FROM_ZERO_ADDRESS");
    require(_spender != address(0), "APPROVE_TO_ZERO_ADDRESS");

    allowances[_owner][_spender] = _amount;
    emit Approval(_owner, _spender, _amount);
  }

  /**
   * @return the amount of shares owned by `_account`.
   */
  function _sharesOf(address _account) internal view returns (uint256) {
    return shares[_account];
  }

  /**
   * @notice Moves `_sharesAmount` shares from `_sender` to `_recipient`.
   *
   * Requirements:
   *
   * - `_sender` cannot be the zero address.
   * - `_recipient` cannot be the zero address.
   * - `_sender` must hold at least `_sharesAmount` shares.
   * - the contract must not be paused.
   */
  function _transferShares(address _sender, address _recipient, uint256 _sharesAmount)
    internal
    whenNotPaused
  {
    require(_sender != address(0), "TRANSFER_FROM_THE_ZERO_ADDRESS");
    require(_recipient != address(0), "TRANSFER_TO_THE_ZERO_ADDRESS");

    _beforeTokenTransfer(_sender, _recipient, _sharesAmount);

    uint256 currentSenderShares = shares[_sender];
    require(_sharesAmount <= currentSenderShares, "TRANSFER_AMOUNT_EXCEEDS_BALANCE");

    shares[_sender] = currentSenderShares - _sharesAmount;
    shares[_recipient] += _sharesAmount;
  }

  /**
   * @notice Creates `_sharesAmount` shares and assigns them to `_recipient`, increasing the total amount of shares.
   *
   * Requirements:
   *
   * - `_recipient` cannot be the zero address.
   * - the contract must not be paused.
   */
  function _mintShares(address _recipient, uint256 _sharesAmount) internal {
    require(_recipient != address(0), "MINT_TO_THE_ZERO_ADDRESS");

    _beforeTokenTransfer(address(0), _recipient, _sharesAmount);

    totalShares += _sharesAmount;

    shares[_recipient] += _sharesAmount;
  }

  /**
   * @notice Destroys `_sharesAmount` shares from `_account`'s holdings, decreasing the total amount of shares.
   * @dev This doesn't decrease the token total supply.
   *
   * Requirements:
   *
   * - `_account` cannot be the zero address.
   * - `_account` must hold at least `_sharesAmount` shares.
   * - the contract must not be paused.
   */
  function _burnShares(address _account, uint256 _sharesAmount) internal {
    require(_account != address(0), "BURN_FROM_THE_ZERO_ADDRESS");

    _beforeTokenTransfer(_account, address(0), _sharesAmount);

    uint256 accountShares = shares[_account];
    require(_sharesAmount <= accountShares, "BURN_AMOUNT_EXCEEDS_BALANCE");

    totalShares -= _sharesAmount;

    shares[_account] = accountShares - _sharesAmount;
  }

  /**
   * @dev Hook that is called before any transfer of tokens. This includes
   * minting and burning.
   *
   * Calling conditions:
   *
   * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
   * will be transferred to `to`.
   * - when `from` is zero, `amount` tokens will be minted for `to`.
   * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
   * - `from` and `to` are never both zero.
   *
   * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
   */
  function _beforeTokenTransfer(address from, address to, uint256) internal view {
    // Check constraints when `transferFrom` is called to facliitate
    // a transfer between two parties that are not `from` or `to`.
    if (from != msg.sender && to != msg.sender) {
      require(_getKYCStatus(msg.sender), "rOUSG: 'sender' address not KYC'd");
    }

    if (from != address(0)) {
      // If not minting
      require(_getKYCStatus(from), "rOUSG: 'from' address not KYC'd");
    }

    if (to != address(0)) {
      // If not burning
      require(_getKYCStatus(to), "rOUSG: 'to' address not KYC'd");
    }
  }

  /**
   * @notice Sets the Oracle address
   * @dev The new oracle must comply with the IRWAOracle interface
   * @param _oracle Address of the new oracle
   */
  function setOracle(address _oracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_oracle == address(0)) {
      revert CannotSetToZeroAddress();
    }
    emit OracleSet(address(oracle), _oracle);
    oracle = IRWAOracle(_oracle);
  }

  /**
   * @notice Sets the token name
   * @param newName New name of the token
   */
  function setName(string memory newName) external onlyRole(DEFAULT_ADMIN_ROLE) {
    emit NameSet(_name, newName);
    _name = newName;
  }

  /**
   * @notice Sets the token symbol
   * @param newSymbol New symbol of the token
   */
  function setSymbol(string memory newSymbol) external onlyRole(DEFAULT_ADMIN_ROLE) {
    emit SymbolSet(_symbol, newSymbol);
    _symbol = newSymbol;
  }

  /**
   * @notice Admin burn function to burn rOUSG tokens from any account
   * @param _account The account to burn tokens from
   * @param _sharesAmount  The amount of OUSG shares to burn
   * @dev Burns shares and transfers OUSG (if any) to `msg.sender`
   */
  function burnShares(address _account, uint256 _sharesAmount) external onlyRole(BURNER_ROLE) {
    require(_sharesAmount > 0, "rOUSG: can't burn zero shares");

    uint256 rOUSGAmount = getROUSGByShares(_sharesAmount);

    _burnShares(_account, _sharesAmount);
    emit TransferShares(_account, address(0), _sharesAmount);

    if (_sharesAmount >= OUSG_TO_ROUSG_SHARES_MULTIPLIER) {
      // forge-lint: disable-next-line(erc20-unchecked-transfer)
      ousg.transfer(msg.sender, _sharesAmount / OUSG_TO_ROUSG_SHARES_MULTIPLIER);
      emit Transfer(_account, address(0), rOUSGAmount);
    }
  }

  function pause() external onlyRole(PAUSER_ROLE) {
    _pause();
  }

  function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _unpause();
  }

  function setKYCRegistry(address registry) external override onlyRole(CONFIGURER_ROLE) {
    _setKYCRegistry(registry);
  }

  function setKYCRequirementGroup(uint256 group) external override onlyRole(CONFIGURER_ROLE) {
    _setKYCRequirementGroup(group);
  }
}
