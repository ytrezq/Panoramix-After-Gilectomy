/**
 * SPDX-License-Identifier: BUSL-1.1
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
 */
pragma solidity 0.8.33;

import {
  AccessControlEnumerableUpgradeable
} from "contracts/external/openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import {
  ERC20BurnableUpgradeable
} from "contracts/external/openzeppelin/contracts-upgradeable/token/ERC20/ERC20BurnableUpgradeable.sol";
import {
  OndoComplianceGMClientUpgradeable
} from "contracts/globalMarkets/gmTokenCompliance/OndoComplianceGMClientUpgradeable.sol";
import {
  TokenPauseManagerClientUpgradeable
} from "contracts/globalMarkets/tokenPauseManager/TokenPauseManagerClientUpgradeable.sol";

/**
 * @title  GMToken
 * @author Ondo Finance
 * @notice Global Markets (GM) token implementation with compliance and pause functionality. These
 *         tokens will follow the BeaconProxy pattern for ease of global upgrades.
 */
contract GMToken is
  ERC20BurnableUpgradeable,
  AccessControlEnumerableUpgradeable,
  OndoComplianceGMClientUpgradeable,
  TokenPauseManagerClientUpgradeable
{
  /// Role for changing the token name, symbol, compliance and token pause manager
  bytes32 public constant CONFIGURER_ROLE = keccak256("CONFIGURER_ROLE");
  /// Role for burning tokens
  bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
  /// Role for minting tokens
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  /// Override for the name allowing the name to be changed
  string private nameOverride;
  /// Override for the symbol allowing the symbol to be changed
  string private symbolOverride;

  /**
   * @notice Emitted when the token name is changed
   * @param  oldName The old token name
   * @param  newName The new token name
   */
  event NameChanged(string oldName, string newName);

  /**
   * @notice Emitted when the token symbol is changed
   * @param  oldSymbol The old token symbol
   * @param  newSymbol The new token symbol
   */
  event SymbolChanged(string oldSymbol, string newSymbol);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @notice Initializes the GMToken contract
   * @param  _nameOverride      The initial name of the token
   * @param  _symbolOverride    The initial symbol of the token
   * @param  _compliance        The address of the compliance contract
   * @param  _tokenPauseManager The address of the token pause manager contract
   * @dev    This function can only be called once during deployment via the proxy pattern
   */
  function initialize(
    string memory _nameOverride,
    string memory _symbolOverride,
    address _compliance,
    address _tokenPauseManager
  ) public initializer {
    __gmToken_init(_nameOverride, _symbolOverride, _compliance, _tokenPauseManager);
  }

  /**
   * @notice Internal initialization function for GMToken
   * @param  _nameOverride      The initial name of the token
   * @param  _symbolOverride    The initial symbol of the token
   * @param  _compliance        The address of the compliance contract
   * @param  _tokenPauseManager The address of the token pause manager contract
   * @dev    Initializes all parent contracts and sets up the GMToken specific state
   */
  function __gmToken_init(
    string memory _nameOverride,
    string memory _symbolOverride,
    address _compliance,
    address _tokenPauseManager
  ) internal onlyInitializing {
    __AccessControlEnumerable_init_unchained();
    __ERC20_init_unchained(_nameOverride, _symbolOverride);
    __OndoComplianceGMClientInitializable_init(_compliance);
    __TokenPauseManagerClientInitializable_init_unchained(_tokenPauseManager);
    __gmToken_init_unchained(_nameOverride, _symbolOverride);
  }

  /**
   * @notice Unchained initialization function for GMToken-specific state
   * @param  _nameOverride   The initial name of the token
   * @param  _symbolOverride The initial symbol of the token
   * @dev    Sets up GMToken-specific state without calling parent initializers
   */
  function __gmToken_init_unchained(string memory _nameOverride, string memory _symbolOverride)
    internal
    onlyInitializing
  {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    nameOverride = _nameOverride;
    symbolOverride = _symbolOverride;
  }

  /**
   * @notice Returns the name of the token
   * @dev    Overrides the default ERC20 name function to return the `nameOverride` variable,
   *         allowing the name to be changed after deployment
   */
  function name() public view virtual override returns (string memory) {
    return nameOverride;
  }

  /**
   * @notice Returns the ticker symbol of the token
   * @dev    Overrides the default ERC20 symbol function to return the `symbolOverride` variable,
   *         allowing the symbol to be changed after deployment
   */
  function symbol() public view virtual override returns (string memory) {
    return symbolOverride;
  }

  /**
   * @notice Sets the token name
   * @param  _nameOverride New token name
   */
  function setName(string memory _nameOverride) external onlyRole(CONFIGURER_ROLE) {
    emit NameChanged(nameOverride, _nameOverride);
    nameOverride = _nameOverride;
  }

  /**
   * @notice Sets the token symbol
   * @param  _symbolOverride New token symbol
   */
  function setSymbol(string memory _symbolOverride) external onlyRole(CONFIGURER_ROLE) {
    emit SymbolChanged(symbolOverride, _symbolOverride);
    symbolOverride = _symbolOverride;
  }

  /**
   * @notice Sets the compliance address
   * @param  _compliance New compliance address
   */
  function setCompliance(address _compliance) external onlyRole(CONFIGURER_ROLE) {
    _setCompliance(_compliance);
  }

  /**
   * @notice Sets the token pause manager address
   * @param  _tokenPauseManager New token pause manager address
   */
  function setTokenPauseManager(address _tokenPauseManager) external onlyRole(CONFIGURER_ROLE) {
    _setTokenPauseManager(_tokenPauseManager);
  }

  /**
   * @notice Hook that is called before any transfer of tokens
   * @param  from   The address tokens are transferred from (0x0 for minting)
   * @param  to     The address tokens are transferred to (0x0 for burning)
   * @param  amount The amount of tokens being transferred
   * @dev    Checks if token is paused and validates compliance for all parties involved
   */
  function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
    super._beforeTokenTransfer(from, to, amount);
    // Revert if the token is paused
    _checkTokenIsPaused();
    // Check constraints when `transferFrom` is called to facilitate
    // a transfer between two parties that are not `from` or `to`.
    if (from != msg.sender && to != msg.sender) {
      _checkIsCompliant(msg.sender);
    }

    if (from != address(0)) {
      // If not minting
      _checkIsCompliant(from);
    }

    if (to != address(0)) {
      // If not burning
      _checkIsCompliant(to);
    }
  }

  /**
   * @notice Mints a specific amount of tokens
   * @param  to The account who will receive the minted tokens
   * @param  amount The amount of tokens to be minted
   * @dev    This function is only callable by an address with the `MINTER_ROLE`
   */
  function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
    _mint(to, amount);
  }

  /**
   * @notice Burns a specific amount of tokens
   * @param  from The account whose tokens will be burned
   * @param  amount The amount of tokens to be burned
   * @dev    This function can be considered an admin-burn and is only callable
   *         by an address with the `BURNER_ROLE`
   */
  function burn(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
    _burn(from, amount);
  }
}
