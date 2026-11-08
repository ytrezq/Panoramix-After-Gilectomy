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
import {BlocklistClientUpgradeable} from "contracts/usdy/blocklist/BlocklistClientUpgradeable.sol";
import {
  SanctionsListClientUpgradeable
} from "contracts/sanctions/SanctionsListClientUpgradeable.sol";
import {IUSDY} from "contracts/usdy/IUSDY.sol";
import {IRWADynamicOracle} from "contracts/rwaOracles/IRWADynamicOracle.sol";

/**
 * @title Interest-bearing ERC20-like token for USDY.
 *
 * rUSDY balances are dynamic and represent the holder's share of the underlying USDY
 * controlled by the protocol. To calculate each account's balance, we do
 *
 *   shares[account] * usdyPrice
 *
 * For example, assume that we have:
 *
 *   usdyPrice = 1.05 (18 decimals)
 *   rusdy.sharesOf(user1) -> 1 (22 decimals)
 *   rusdy.sharesOf(user2) -> 4 (22 decimals)
 *   rusdy.balanceOf(rusdy) -> 5 USDY (18 decimals)
 *
 * Below would be the balances of the users:
 *
 *   balanceOf(user1) -> 1.05 rUSDY (18 decimals)
 *   balanceOf(user2) -> 4.2 rUSDY (18 decimals)
 *
 * Since balances of all token holders change when the price of USDY changes, this
 * token cannot fully implement ERC20 standard: it only emits `Transfer` events
 * upon explicit transfer between holders. In contrast, when total amount of pooled
 * Cash increases, no `Transfer` events are generated: doing so would require emitting
 * an event for each token holder and thus running an unbounded loop.
 *
 */

contract rUSDY is
  Initializable,
  ContextUpgradeable,
  PausableUpgradeable,
  AccessControlEnumerableUpgradeable,
  BlocklistClientUpgradeable,
  SanctionsListClientUpgradeable,
  IERC20Upgradeable,
  IERC20MetadataUpgradeable
{
  /**
   * @dev rUSDY balances are dynamic and are calculated based on the accounts' shares (USDY)
   * and the the price of USDY. Account shares aren't
   * normalized, so the contract also stores the sum of all shares to calculate
   * each account's token balance which equals to:
   *
   *   shares[account] * usdyPrice
   */
  mapping(address => uint256) private shares;

  /// @dev Allowances are nominated in tokens, not token shares.
  mapping(address => mapping(address => uint256)) private allowances;

  // Total shares in existence
  uint256 public totalShares;

  // Address of the oracle that updates `usdyPrice`
  IRWADynamicOracle public oracle;

  // Address of the USDY token
  IUSDY public usdy;

  // Used to scale up usdy amount -> shares
  uint256 public constant USDY_TO_RUSDY_SHARES_MULTIPLIER = 10_000;

  // Name of the token
  string internal _name;

  // Symbol of the token
  string internal _symbol;

  // Error when redeeming shares < `USDY_TO_RUSDY_SHARES_MULTIPLIER`
  error UnwrapTooSmall();

  // Error when setting the oracle address to zero
  error CannotSetToZeroAddress();

  /// @dev Role based access control roles
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
  bytes32 public constant BURNER_ROLE = keccak256("BURN_ROLE");
  bytes32 public constant LIST_CONFIGURER_ROLE = keccak256("LIST_CONFIGURER_ROLE");

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address blocklist,
    address sanctionsList,
    address _usdy,
    address guardian,
    address _oracle
  ) public virtual initializer {
    __rUSDY_init(blocklist, sanctionsList, _usdy, guardian, _oracle);
  }

  function __rUSDY_init(
    address blocklist,
    address sanctionsList,
    address _usdy,
    address guardian,
    address _oracle
  ) internal onlyInitializing {
    __BlocklistClientInitializable_init(blocklist);
    __SanctionsListClientInitializable_init(sanctionsList);
    __rUSDY_init_unchained(_usdy, guardian, _oracle);
  }

  function __rUSDY_init_unchained(address _usdy, address guardian, address _oracle)
    internal
    onlyInitializing
  {
    usdy = IUSDY(_usdy);
    oracle = IRWADynamicOracle(_oracle);
    _grantRole(DEFAULT_ADMIN_ROLE, guardian);
    _grantRole(PAUSER_ROLE, guardian);
    _grantRole(BURNER_ROLE, guardian);
    _grantRole(LIST_CONFIGURER_ROLE, guardian);
    _name = "Ondo U.S. Dollar Yield (Rebasing)";
    _symbol = "rUSDY";
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
   * @notice An executed shares transfer.
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
    return (totalShares * oracle.getPrice()) / (1e18 * USDY_TO_RUSDY_SHARES_MULTIPLIER);
  }

  /**
   * @return the amount of tokens owned by the `_account`.
   *
   * @dev Balances are dynamic and equal the `_account`'s USDY shares multiplied
   *      by the price of USDY
   */
  function balanceOf(address _account) public view returns (uint256) {
    return (_sharesOf(_account) * oracle.getPrice()) / (1e18 * USDY_TO_RUSDY_SHARES_MULTIPLIER);
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
   * @dev This is the equivalent to the amount of USDY wrapped by `_account`.
   */
  function sharesOf(address _account) public view returns (uint256) {
    return _sharesOf(_account);
  }

  /**
   * @return the amount of shares that corresponds to `_rUSDYAmount` of rUSDY
   */
  function getSharesByRUSDY(uint256 _rUSDYAmount) public view returns (uint256) {
    return (_rUSDYAmount * 1e18 * USDY_TO_RUSDY_SHARES_MULTIPLIER) / oracle.getPrice();
  }

  /**
   * @return the amount of rUSDY that corresponds to `_shares` of usdy.
   */
  function getRUSDYByShares(uint256 _shares) public view returns (uint256) {
    return (_shares * oracle.getPrice()) / (1e18 * USDY_TO_RUSDY_SHARES_MULTIPLIER);
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
    uint256 tokensAmount = getRUSDYByShares(_sharesAmount);
    emit Transfer(msg.sender, _recipient, tokensAmount);
    return tokensAmount;
  }

  /**
   * @notice Function called by users to wrap their USDY tokens
   *
   * @param _USDYAmount The amount of USDY Tokens to wrap
   *
   * @dev Sanctions and Blocklist checks implicit in USDY Transfer
   */
  function wrap(uint256 _USDYAmount) external whenNotPaused {
    require(_USDYAmount > 0, "rUSDY: can't wrap zero USDY tokens");
    uint256 usdySharesAmount = _USDYAmount * USDY_TO_RUSDY_SHARES_MULTIPLIER;
    _mintShares(msg.sender, usdySharesAmount);
    // forge-lint: disable-next-line(erc20-unchecked-transfer)
    usdy.transferFrom(msg.sender, address(this), _USDYAmount);
    emit Transfer(address(0), msg.sender, getRUSDYByShares(usdySharesAmount));
    emit TransferShares(address(0), msg.sender, usdySharesAmount);
  }

  /**
   * @notice Function called by users to unwrap their rUSDY tokens by rUSDY amount
   *
   * @param _rUSDYAmount The amount of rUSDY to unwrap
   *
   * @dev Sanctions and Blocklist checks implicit in USDY Transfer
   */
  function unwrap(uint256 _rUSDYAmount) external whenNotPaused {
    require(_rUSDYAmount > 0, "rUSDY: can't unwrap zero rUSDY tokens");
    uint256 usdySharesAmount = getSharesByRUSDY(_rUSDYAmount);
    if (usdySharesAmount < USDY_TO_RUSDY_SHARES_MULTIPLIER) {
      revert UnwrapTooSmall();
    }
    _burnShares(msg.sender, usdySharesAmount);
    // forge-lint: disable-next-line(erc20-unchecked-transfer)
    usdy.transfer(msg.sender, usdySharesAmount / USDY_TO_RUSDY_SHARES_MULTIPLIER);
    emit Transfer(msg.sender, address(0), _rUSDYAmount);
    emit TransferShares(msg.sender, address(0), usdySharesAmount);
  }

  /**
   * @notice Function called by users to unwrap their rUSDY tokens by shares
   *
   * @param _sharesAmount The amount of shares to transfer
   *
   * @dev Sanctions and Blocklist checks implicit in USDY Transfer
   * @dev This is a more precise unwrap, as it avoids the division by price when converting rUSDY to shares
   */
  function unwrapShares(uint256 _sharesAmount) external whenNotPaused {
    if (_sharesAmount < USDY_TO_RUSDY_SHARES_MULTIPLIER) {
      revert UnwrapTooSmall();
    }

    uint256 rUSDYAmount = getRUSDYByShares(_sharesAmount);

    _burnShares(msg.sender, _sharesAmount);
    // forge-lint: disable-next-line(erc20-unchecked-transfer)
    usdy.transfer(msg.sender, _sharesAmount / USDY_TO_RUSDY_SHARES_MULTIPLIER);
    emit Transfer(msg.sender, address(0), rUSDYAmount);
    emit TransferShares(msg.sender, address(0), _sharesAmount);
  }

  /**
   * @notice Moves `_amount` tokens from `_sender` to `_recipient`.
   * Emits a `Transfer` event.
   * Emits a `TransferShares` event.
   */
  function _transfer(address _sender, address _recipient, uint256 _amount) internal {
    uint256 _sharesToTransfer = getSharesByRUSDY(_amount);
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
      require(!_isBlocked(msg.sender), "rUSDY: 'sender' address blocked");
      require(!_isSanctioned(msg.sender), "rUSDY: 'sender' address sanctioned");
    }

    if (from != address(0)) {
      // If not minting
      require(!_isBlocked(from), "rUSDY: 'from' address blocked");
      require(!_isSanctioned(from), "rUSDY: 'from' address sanctioned");
    }

    if (to != address(0)) {
      // If not burning
      require(!_isBlocked(to), "rUSDY: 'to' address blocked");
      require(!_isSanctioned(to), "rUSDY: 'to' address sanctioned");
    }
  }

  /**
   * @notice Sets the Oracle address
   * @dev The new oracle must comply with the IRWADynamicOracle interface
   * @param _oracle Address of the new oracle
   */
  function setOracle(address _oracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_oracle == address(0)) {
      revert CannotSetToZeroAddress();
    }
    emit OracleSet(address(oracle), _oracle);
    oracle = IRWADynamicOracle(_oracle);
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
   * @notice Admin burn function to burn rUSDY tokens from any account
   * @param _account The account to burn tokens from
   * @param _sharesAmount  The amount of USDY shares to burn
   * @dev Burns shares and transfers USDY (if any) to `msg.sender`
   */
  function burnShares(address _account, uint256 _sharesAmount) external onlyRole(BURNER_ROLE) {
    require(_sharesAmount > 0, "rUSDY: can't burn zero shares");

    uint256 rUSDYAmount = getRUSDYByShares(_sharesAmount);

    _burnShares(_account, _sharesAmount);
    emit TransferShares(_account, address(0), _sharesAmount);

    if (_sharesAmount >= USDY_TO_RUSDY_SHARES_MULTIPLIER) {
      // forge-lint: disable-next-line(erc20-unchecked-transfer)
      usdy.transfer(msg.sender, _sharesAmount / USDY_TO_RUSDY_SHARES_MULTIPLIER);
      emit Transfer(_account, address(0), rUSDYAmount);
    }
  }

  function pause() external onlyRole(PAUSER_ROLE) {
    _pause();
  }

  function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _unpause();
  }

  /**
   * @notice Sets the blocklist address
   *
   * @param blocklist New blocklist address
   */
  function setBlocklist(address blocklist) external override onlyRole(LIST_CONFIGURER_ROLE) {
    _setBlocklist(blocklist);
  }

  /**
   * @notice Sets the sanctions list address
   *
   * @param sanctionsList New sanctions list address
   */
  function setSanctionsList(address sanctionsList)
    external
    override
    onlyRole(LIST_CONFIGURER_ROLE)
  {
    _setSanctionsList(sanctionsList);
  }
}
