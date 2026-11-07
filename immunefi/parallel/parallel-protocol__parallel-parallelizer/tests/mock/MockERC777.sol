// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";

interface IERC777Recipient {
  function tokensReceived(
    address operator,
    address from,
    address to,
    uint256 amount,
    bytes calldata userData,
    bytes calldata operatorData
  )
    external;
}

interface IERC777Sender {
  function tokensToSend(
    address operator,
    address from,
    address to,
    uint256 amount,
    bytes calldata userData,
    bytes calldata operatorData
  )
    external;
}

interface IERC777 {
  event Minted(address indexed operator, address indexed to, uint256 amount, bytes data, bytes operatorData);
  event Burned(address indexed operator, address indexed from, uint256 amount, bytes data, bytes operatorData);
  event AuthorizedOperator(address indexed operator, address indexed tokenHolder);
  event RevokedOperator(address indexed operator, address indexed tokenHolder);
  event Sent(
    address indexed operator, address indexed from, address indexed to, uint256 amount, bytes data, bytes operatorData
  );

  function name() external view returns (string memory);
  function symbol() external view returns (string memory);
  function granularity() external view returns (uint256);
  function totalSupply() external view returns (uint256);
  function balanceOf(address owner) external view returns (uint256);
  function send(address recipient, uint256 amount, bytes calldata data) external;
  function burn(uint256 amount, bytes calldata data) external;
  function isOperatorFor(address operator, address tokenHolder) external view returns (bool);
  function authorizeOperator(address operator) external;
  function revokeOperator(address operator) external;
  function defaultOperators() external view returns (address[] memory);
  function operatorSend(
    address sender,
    address recipient,
    uint256 amount,
    bytes calldata data,
    bytes calldata operatorData
  )
    external;
  function operatorBurn(address account, uint256 amount, bytes calldata data, bytes calldata operatorData) external;
}

/**
 * @dev Implementation of the {IERC777} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 *
 * Support for ERC20 is included in this contract, as specified by the EIP: both
 * the ERC777 and ERC20 interfaces can be safely used when interacting with it.
 * Both {IERC777-Sent} and {IERC20-Transfer} events are emitted on token
 * movements.
 *
 * Additionally, the {IERC777-granularity} value is hard-coded to `1`, meaning that there
 * are no special restrictions in the amount of tokens that created, moved, or
 * destroyed. This makes integration with ERC20 applications seamless.
 *
 * CAUTION: This file is deprecated as of v4.9 and will be removed in the next major release.
 */
contract ERC777 is Context, IERC777, IERC20 {
  using Address for address;

  IERC1820Registry internal constant _ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

  mapping(address => uint256) private _balances;

  uint256 private _totalSupply;

  string private _name;
  string private _symbol;

  bytes32 private constant _TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
  bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

  // This isn't ever read from - it's only used to respond to the defaultOperators query.
  address[] private _defaultOperatorsArray;

  // Immutable, but accounts may revoke them (tracked in __revokedDefaultOperators).
  mapping(address => bool) private _defaultOperators;

  // For each account, a mapping of its operators and revoked default operators.
  mapping(address => mapping(address => bool)) private _operators;
  mapping(address => mapping(address => bool)) private _revokedDefaultOperators;

  // ERC20-allowances
  mapping(address => mapping(address => uint256)) private _allowances;

  /**
   * @dev `defaultOperators` may be an empty array.
   */
  constructor(string memory name_, string memory symbol_, address[] memory defaultOperators_) {
    _name = name_;
    _symbol = symbol_;

    _defaultOperatorsArray = defaultOperators_;
    for (uint256 i = 0; i < defaultOperators_.length; i++) {
      _defaultOperators[defaultOperators_[i]] = true;
    }

    // register interfaces
    _ERC1820_REGISTRY.setInterfaceImplementer(address(this), keccak256("ERC777Token"), address(this));
    _ERC1820_REGISTRY.setInterfaceImplementer(address(this), keccak256("ERC20Token"), address(this));
  }

  /**
   * @dev See {IERC777-name}.
   */
  function name() public view virtual override returns (string memory) {
    return _name;
  }

  /**
   * @dev See {IERC777-symbol}.
   */
  function symbol() public view virtual override returns (string memory) {
    return _symbol;
  }

  /**
   * @dev See {ERC20-decimals}.
   *
   * Always returns 18, as per the
   * [ERC777 EIP](https://eips.ethereum.org/EIPS/eip-777#backward-compatibility).
   */
  function decimals() public pure virtual returns (uint8) {
    return 18;
  }

  /**
   * @dev See {IERC777-granularity}.
   *
   * This implementation always returns `1`.
   */
  function granularity() public view virtual override returns (uint256) {
    return 1;
  }

  /**
   * @dev See {IERC777-totalSupply}.
   */
  function totalSupply() public view virtual override(IERC20, IERC777) returns (uint256) {
    return _totalSupply;
  }

  /**
   * @dev Returns the amount of tokens owned by an account (`tokenHolder`).
   */
  function balanceOf(address tokenHolder) public view virtual override(IERC20, IERC777) returns (uint256) {
    return _balances[tokenHolder];
  }

  /**
   * @dev See {IERC777-send}.
   *
   * Also emits a {IERC20-Transfer} event for ERC20 compatibility.
   */
  function send(address recipient, uint256 amount, bytes memory data) public virtual override {
    _send(_msgSender(), recipient, amount, data, "", true);
  }

  /**
   * @dev See {IERC20-transfer}.
   *
   * Unlike `send`, `recipient` is _not_ required to implement the {IERC777Recipient}
   * interface if it is a contract.
   *
   * Also emits a {Sent} event.
   */
  function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
    _send(_msgSender(), recipient, amount, "", "", false);
    return true;
  }

  /**
   * @dev See {IERC777-burn}.
   *
   * Also emits a {IERC20-Transfer} event for ERC20 compatibility.
   */
  function burn(uint256 amount, bytes memory data) public virtual override {
    _burn(_msgSender(), amount, data, "");
  }

  /**
   * @dev See {IERC777-isOperatorFor}.
   */
  function isOperatorFor(address operator, address tokenHolder) public view virtual override returns (bool) {
    return operator == tokenHolder || (_defaultOperators[operator] && !_revokedDefaultOperators[tokenHolder][operator])
      || _operators[tokenHolder][operator];
  }

  /**
   * @dev See {IERC777-authorizeOperator}.
   */
  function authorizeOperator(address operator) public virtual override {
    require(_msgSender() != operator, "ERC777: authorizing self as operator");

    if (_defaultOperators[operator]) {
      delete _revokedDefaultOperators[_msgSender()][operator];
    } else {
      _operators[_msgSender()][operator] = true;
    }

    emit AuthorizedOperator(operator, _msgSender());
  }

  /**
   * @dev See {IERC777-revokeOperator}.
   */
  function revokeOperator(address operator) public virtual override {
    require(operator != _msgSender(), "ERC777: revoking self as operator");

    if (_defaultOperators[operator]) {
      _revokedDefaultOperators[_msgSender()][operator] = true;
    } else {
      delete _operators[_msgSender()][operator];
    }

    emit RevokedOperator(operator, _msgSender());
  }

  /**
   * @dev See {IERC777-defaultOperators}.
   */
  function defaultOperators() public view virtual override returns (address[] memory) {
    return _defaultOperatorsArray;
  }

  /**
   * @dev See {IERC777-operatorSend}.
   *
   * Emits {Sent} and {IERC20-Transfer} events.
   */
  function operatorSend(
    address sender,
    address recipient,
    uint256 amount,
    bytes memory data,
    bytes memory operatorData
  )
    public
    virtual
    override
  {
    require(isOperatorFor(_msgSender(), sender), "ERC777: caller is not an operator for holder");
    _send(sender, recipient, amount, data, operatorData, true);
  }

  /**
   * @dev See {IERC777-operatorBurn}.
   *
   * Emits {Burned} and {IERC20-Transfer} events.
   */
  function operatorBurn(
    address account,
    uint256 amount,
    bytes memory data,
    bytes memory operatorData
  )
    public
    virtual
    override
  {
    require(isOperatorFor(_msgSender(), account), "ERC777: caller is not an operator for holder");
    _burn(account, amount, data, operatorData);
  }

  /**
   * @dev See {IERC20-allowance}.
   *
   * Note that operator and allowance concepts are orthogonal: operators may
   * not have allowance, and accounts with allowance may not be operators
   * themselves.
   */
  function allowance(address holder, address spender) public view virtual override returns (uint256) {
    return _allowances[holder][spender];
  }

  /**
   * @dev See {IERC20-approve}.
   *
   * NOTE: If `value` is the maximum `uint256`, the allowance is not updated on
   * `transferFrom`. This is semantically equivalent to an infinite approval.
   *
   * Note that accounts cannot have allowance issued by their operators.
   */
  function approve(address spender, uint256 value) public virtual override returns (bool) {
    address holder = _msgSender();
    _approve(holder, spender, value);
    return true;
  }

  /**
   * @dev See {IERC20-transferFrom}.
   *
   * NOTE: Does not update the allowance if the current allowance
   * is the maximum `uint256`.
   *
   * Note that operator and allowance concepts are orthogonal: operators cannot
   * call `transferFrom` (unless they have allowance), and accounts with
   * allowance cannot call `operatorSend` (unless they are operators).
   *
   * Emits {Sent}, {IERC20-Transfer} and {IERC20-Approval} events.
   */
  function transferFrom(address holder, address recipient, uint256 amount) public virtual override returns (bool) {
    address spender = _msgSender();
    _spendAllowance(holder, spender, amount);
    _send(holder, recipient, amount, "", "", false);
    return true;
  }

  /**
   * @dev Creates `amount` tokens and assigns them to `account`, increasing
   * the total supply.
   *
   * If a send hook is registered for `account`, the corresponding function
   * will be called with the caller address as the `operator` and with
   * `userData` and `operatorData`.
   *
   * See {IERC777Sender} and {IERC777Recipient}.
   *
   * Emits {Minted} and {IERC20-Transfer} events.
   *
   * Requirements
   *
   * - `account` cannot be the zero address.
   * - if `account` is a contract, it must implement the {IERC777Recipient}
   * interface.
   */
  function _mint(address account, uint256 amount, bytes memory userData, bytes memory operatorData) internal virtual {
    _mint(account, amount, userData, operatorData, true);
  }

  /**
   * @dev Creates `amount` tokens and assigns them to `account`, increasing
   * the total supply.
   *
   * If `requireReceptionAck` is set to true, and if a send hook is
   * registered for `account`, the corresponding function will be called with
   * `operator`, `data` and `operatorData`.
   *
   * See {IERC777Sender} and {IERC777Recipient}.
   *
   * Emits {Minted} and {IERC20-Transfer} events.
   *
   * Requirements
   *
   * - `account` cannot be the zero address.
   * - if `account` is a contract, it must implement the {IERC777Recipient}
   * interface.
   */
  function _mint(
    address account,
    uint256 amount,
    bytes memory userData,
    bytes memory operatorData,
    bool requireReceptionAck
  )
    internal
    virtual
  {
    require(account != address(0), "ERC777: mint to the zero address");

    address operator = _msgSender();

    _beforeTokenTransfer(operator, address(0), account, amount);

    // Update state variables
    _totalSupply += amount;
    _balances[account] += amount;

    _callTokensReceived(operator, address(0), account, amount, userData, operatorData, requireReceptionAck);

    emit Minted(operator, account, amount, userData, operatorData);
    emit Transfer(address(0), account, amount);
  }

  /**
   * @dev Send tokens
   * @param from address token holder address
   * @param to address recipient address
   * @param amount uint256 amount of tokens to transfer
   * @param userData bytes extra information provided by the token holder (if any)
   * @param operatorData bytes extra information provided by the operator (if any)
   * @param requireReceptionAck if true, contract recipients are required to implement ERC777TokensRecipient
   */
  function _send(
    address from,
    address to,
    uint256 amount,
    bytes memory userData,
    bytes memory operatorData,
    bool requireReceptionAck
  )
    internal
    virtual
  {
    require(from != address(0), "ERC777: transfer from the zero address");
    require(to != address(0), "ERC777: transfer to the zero address");

    address operator = _msgSender();

    _callTokensToSend(operator, from, to, amount, userData, operatorData);

    _move(operator, from, to, amount, userData, operatorData);

    _callTokensReceived(operator, from, to, amount, userData, operatorData, requireReceptionAck);
  }

  /**
   * @dev Burn tokens
   * @param from address token holder address
   * @param amount uint256 amount of tokens to burn
   * @param data bytes extra information provided by the token holder
   * @param operatorData bytes extra information provided by the operator (if any)
   */
  function _burn(address from, uint256 amount, bytes memory data, bytes memory operatorData) internal virtual {
    require(from != address(0), "ERC777: burn from the zero address");

    address operator = _msgSender();

    _callTokensToSend(operator, from, address(0), amount, data, operatorData);

    _beforeTokenTransfer(operator, from, address(0), amount);

    // Update state variables
    uint256 fromBalance = _balances[from];
    require(fromBalance >= amount, "ERC777: burn amount exceeds balance");
    unchecked {
      _balances[from] = fromBalance - amount;
    }
    _totalSupply -= amount;

    emit Burned(operator, from, amount, data, operatorData);
    emit Transfer(from, address(0), amount);
  }

  function _move(
    address operator,
    address from,
    address to,
    uint256 amount,
    bytes memory userData,
    bytes memory operatorData
  )
    private
  {
    _beforeTokenTransfer(operator, from, to, amount);

    uint256 fromBalance = _balances[from];
    require(fromBalance >= amount, "ERC777: transfer amount exceeds balance");
    unchecked {
      _balances[from] = fromBalance - amount;
    }
    _balances[to] += amount;

    emit Sent(operator, from, to, amount, userData, operatorData);
    emit Transfer(from, to, amount);
  }

  /**
   * @dev See {ERC20-_approve}.
   *
   * Note that accounts cannot have allowance issued by their operators.
   */
  function _approve(address holder, address spender, uint256 value) internal virtual {
    require(holder != address(0), "ERC777: approve from the zero address");
    require(spender != address(0), "ERC777: approve to the zero address");

    _allowances[holder][spender] = value;
    emit Approval(holder, spender, value);
  }

  /**
   * @dev Call from.tokensToSend() if the interface is registered
   * @param operator address operator requesting the transfer
   * @param from address token holder address
   * @param to address recipient address
   * @param amount uint256 amount of tokens to transfer
   * @param userData bytes extra information provided by the token holder (if any)
   * @param operatorData bytes extra information provided by the operator (if any)
   */
  function _callTokensToSend(
    address operator,
    address from,
    address to,
    uint256 amount,
    bytes memory userData,
    bytes memory operatorData
  )
    private
  {
    address implementer = _ERC1820_REGISTRY.getInterfaceImplementer(from, _TOKENS_SENDER_INTERFACE_HASH);
    if (implementer != address(0)) {
      IERC777Sender(implementer).tokensToSend(operator, from, to, amount, userData, operatorData);
    }
  }

  /**
   * @dev Call to.tokensReceived() if the interface is registered. Reverts if the recipient is a contract but
   * tokensReceived() was not registered for the recipient
   * @param operator address operator requesting the transfer
   * @param from address token holder address
   * @param to address recipient address
   * @param amount uint256 amount of tokens to transfer
   * @param userData bytes extra information provided by the token holder (if any)
   * @param operatorData bytes extra information provided by the operator (if any)
   * @param requireReceptionAck if true, contract recipients are required to implement ERC777TokensRecipient
   */
  function _callTokensReceived(
    address operator,
    address from,
    address to,
    uint256 amount,
    bytes memory userData,
    bytes memory operatorData,
    bool requireReceptionAck
  )
    private
  {
    address implementer = _ERC1820_REGISTRY.getInterfaceImplementer(to, _TOKENS_RECIPIENT_INTERFACE_HASH);
    if (implementer != address(0)) {
      IERC777Recipient(implementer).tokensReceived(operator, from, to, amount, userData, operatorData);
    }
  }

  /**
   * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
   *
   * Does not update the allowance amount in case of infinite allowance.
   * Revert if not enough allowance is available.
   *
   * Might emit an {IERC20-Approval} event.
   */
  function _spendAllowance(address owner, address spender, uint256 amount) internal virtual {
    uint256 currentAllowance = allowance(owner, spender);
    if (currentAllowance != type(uint256).max) {
      require(currentAllowance >= amount, "ERC777: insufficient allowance");
      unchecked {
        _approve(owner, spender, currentAllowance - amount);
      }
    }
  }

  /**
   * @dev Hook that is called before any token transfer. This includes
   * calls to {send}, {transfer}, {operatorSend}, {transferFrom}, minting and burning.
   *
   * Calling conditions:
   *
   * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
   * will be to transferred to `to`.
   * - when `from` is zero, `amount` tokens will be minted for `to`.
   * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
   * - `from` and `to` are never both zero.
   *
   * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
   */
  function _beforeTokenTransfer(address operator, address from, address to, uint256 amount) internal virtual { }
}

/**
 * @dev Interface for an ERC1820 implementer, as defined in the
 * https://eips.ethereum.org/EIPS/eip-1820#interface-implementation-erc1820implementerinterface[EIP].
 * Used by contracts that will be registered as implementers in the
 * {IERC1820Registry}.
 */
interface IERC1820Implementer {
  /**
   * @dev Returns a special value (`ERC1820_ACCEPT_MAGIC`) if this contract
   * implements `interfaceHash` for `account`.
   *
   * See {IERC1820Registry-setInterfaceImplementer}.
   */
  function canImplementInterfaceForAddress(bytes32 interfaceHash, address account) external view returns (bytes32);
}

/**
 * @dev Interface of the global ERC1820 Registry, as defined in the
 * https://eips.ethereum.org/EIPS/eip-1820[EIP]. Accounts may register
 * implementers for interfaces in this registry, as well as query support.
 *
 * Implementers may be shared by multiple accounts, and can also implement more
 * than a single interface for each account. Contracts can implement interfaces
 * for themselves, but externally-owned accounts (EOA) must delegate this to a
 * contract.
 *
 * {IERC165} interfaces can also be queried via the registry.
 *
 * For an in-depth explanation and source code analysis, see the EIP text.
 */
interface IERC1820Registry {
  event InterfaceImplementerSet(address indexed account, bytes32 indexed interfaceHash, address indexed implementer);

  event ManagerChanged(address indexed account, address indexed newManager);

  /**
   * @dev Sets `newManager` as the manager for `account`. A manager of an
   * account is able to set interface implementers for it.
   *
   * By default, each account is its own manager. Passing a value of `0x0` in
   * `newManager` will reset the manager to this initial state.
   *
   * Emits a {ManagerChanged} event.
   *
   * Requirements:
   *
   * - the caller must be the current manager for `account`.
   */
  function setManager(address account, address newManager) external;

  /**
   * @dev Returns the manager for `account`.
   *
   * See {setManager}.
   */
  function getManager(address account) external view returns (address);

  /**
   * @dev Sets the `implementer` contract as ``account``'s implementer for
   * `interfaceHash`.
   *
   * `account` being the zero address is an alias for the caller's address.
   * The zero address can also be used in `implementer` to remove an old one.
   *
   * See {interfaceHash} to learn how these are created.
   *
   * Emits an {InterfaceImplementerSet} event.
   *
   * Requirements:
   *
   * - the caller must be the current manager for `account`.
   * - `interfaceHash` must not be an {IERC165} interface id (i.e. it must not
   * end in 28 zeroes).
   * - `implementer` must implement {IERC1820Implementer} and return true when
   * queried for support, unless `implementer` is the caller. See
   * {IERC1820Implementer-canImplementInterfaceForAddress}.
   */
  function setInterfaceImplementer(address account, bytes32 _interfaceHash, address implementer) external;

  /**
   * @dev Returns the implementer of `interfaceHash` for `account`. If no such
   * implementer is registered, returns the zero address.
   *
   * If `interfaceHash` is an {IERC165} interface id (i.e. it ends with 28
   * zeroes), `account` will be queried for support of it.
   *
   * `account` being the zero address is an alias for the caller's address.
   */
  function getInterfaceImplementer(address account, bytes32 _interfaceHash) external view returns (address);

  /**
   * @dev Returns the interface hash for an `interfaceName`, as defined in the
   * corresponding
   * https://eips.ethereum.org/EIPS/eip-1820#interface-name[section of the EIP].
   */
  function interfaceHash(string calldata interfaceName) external pure returns (bytes32);

  /**
   * @notice Updates the cache with whether the contract implements an ERC165 interface or not.
   * @param account Address of the contract for which to update the cache.
   * @param interfaceId ERC165 interface for which to update the cache.
   */
  function updateERC165Cache(address account, bytes4 interfaceId) external;

  /**
   * @notice Checks whether a contract implements an ERC165 interface or not.
   * If the result is not cached a direct lookup on the contract address is performed.
   * If the result is not cached or the cached value is out-of-date, the cache MUST be updated manually by calling
   * {updateERC165Cache} with the contract address.
   * @param account Address of the contract to check.
   * @param interfaceId ERC165 interface to check.
   * @return True if `account` implements `interfaceId`, false otherwise.
   */
  function implementsERC165Interface(address account, bytes4 interfaceId) external view returns (bool);

  /**
   * @notice Checks whether a contract implements an ERC165 interface or not without using or updating the cache.
   * @param account Address of the contract to check.
   * @param interfaceId ERC165 interface to check.
   * @return True if `account` implements `interfaceId`, false otherwise.
   */
  function implementsERC165InterfaceNoCache(address account, bytes4 interfaceId) external view returns (bool);
}

contract MockERC777 is ERC777 {
  event Minting(address indexed _to, address indexed _minter, uint256 _amount);

  event Burning(address indexed _from, address indexed _burner, uint256 _amount);

  constructor(string memory name_, string memory symbol_, uint8 decimal_) ERC777(name_, symbol_, new address[](0)) { }

  function mint(address account, uint256 amount) external {
    _mint(account, amount, "", "");
    emit Minting(account, msg.sender, amount);
  }

  function burn(address account, uint256 amount) public {
    _burn(account, amount, "", "");
    emit Burning(account, msg.sender, amount);
  }

  function setAllowance(address from, address to) public {
    _approve(from, to, type(uint256).max);
  }
}
