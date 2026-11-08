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
  ERC20PresetMinterPauserUpgradeable
} from "contracts/external/openzeppelin/contracts-upgradeable/token/ERC20/ERC20PresetMinterPauserUpgradeable.sol";
import {
  OndoComplianceGMClientUpgradeable
} from "contracts/globalMarkets/gmTokenCompliance/OndoComplianceGMClientUpgradeable.sol";

/**
 * @title  USDon
 * @author Ondo Finance
 * @notice Ondo USD (USDon) token implementation with compliance features
 *         The token supports minting, burning, pausing, and can be configured with custom name/symbol.
 */
contract USDon is ERC20PresetMinterPauserUpgradeable, OndoComplianceGMClientUpgradeable {
  /// Role for changing the token name, symbol, and compliance
  bytes32 public constant CONFIGURER_ROLE = keccak256("CONFIGURER_ROLE");
  /// Role for burning tokens
  bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
  /// Role for unpausing the contract
  bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
  /// Override for the name allowing the name to be changed
  string private nameOverride;
  /// Override for the symbol allowing the symbol to be changed
  string private symbolOverride;

  /**
   * @notice Emitted when the token symbol is changed
   * @param  oldSymbol The old token symbol
   * @param  newSymbol The new token symbol
   */
  event SymbolChanged(string oldSymbol, string newSymbol);

  /**
   * @notice Emitted when the token name is changed
   * @param  oldName The old token name
   * @param  newName The new token name
   */
  event NameChanged(string oldName, string newName);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @notice Initializes the USDon contract
   * @param  _nameOverride   The initial name of the token
   * @param  _symbolOverride The initial symbol of the token
   * @param  _compliance     The address of the compliance contract
   * @dev    This function can only be called once during deployment via the proxy pattern
   */
  function initialize(
    string memory _nameOverride,
    string memory _symbolOverride,
    address _compliance
  ) public initializer {
    __USDon_init(_nameOverride, _symbolOverride, _compliance);
  }

  /**
   * @notice Internal initialization function for USDon
   * @param  _nameOverride   The initial name of the token
   * @param  _symbolOverride The initial symbol of the token
   * @param  _compliance     The address of the compliance contract
   * @dev    Initializes all parent contracts and sets up the USDon specific state
   */
  function __USDon_init(
    string memory _nameOverride,
    string memory _symbolOverride,
    address _compliance
  ) internal onlyInitializing {
    __ERC20PresetMinterPauser_init(_nameOverride, _symbolOverride);
    __OndoComplianceGMClientInitializable_init(_compliance);
    __USDon_init_unchained(_nameOverride, _symbolOverride);
  }

  /**
   * @notice Unchained initialization function for USDon-specific state
   * @param  _nameOverride   The initial name of the token
   * @param  _symbolOverride The initial symbol of the token
   * @dev    Sets up USDon-specific state without calling parent initializers
   */
  function __USDon_init_unchained(string memory _nameOverride, string memory _symbolOverride)
    internal
    onlyInitializing
  {
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
   * @notice Hook that is called before any transfer of tokens
   * @param  from   The address tokens are transferred from (0x0 for minting)
   * @param  to     The address tokens are transferred to (0x0 for burning)
   * @param  amount The amount of tokens being transferred
   * @dev    Validates compliance for all parties involved in the transfer
   */
  function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
    super._beforeTokenTransfer(from, to, amount);
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
   * @notice Burns a specific amount of tokens
   * @param  from   The account whose tokens will be burned
   * @param  amount The amount of token to be burned
   * @dev    This function can be considered an admin-burn and is only callable
   *         by an address with the `BURNER_ROLE`
   */
  function burn(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
    _burn(from, amount);
  }

  /**
   * @notice Unpauses the contract
   * @dev    There is already an unpause function defined in ERC20PresetMinterPauserUpgradeable, however it
   *         checks for the PAUSER_ROLE. By overriding this function, we only allow the UNPAUSER_ROLE to unpause
   *         the contract as it will have a higher threshold of trust.
   */
  function unpause() public override onlyRole(UNPAUSER_ROLE) {
    _unpause();
  }
}
