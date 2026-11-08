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
  Initializable
} from "contracts/external/openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import {
  IOndoComplianceGMView
} from "contracts/globalMarkets/gmTokenCompliance/IOndoComplianceGMView.sol";

/**
 * @title  ComplianceClient
 * @author Ondo Finance
 * @notice This abstract contract manages state for upgradeable compliance
 *         clients
 */
abstract contract OndoComplianceGMClientUpgradeable is Initializable {
  /// Compliance contract
  IOndoComplianceGMView public compliance;

  /**
   * @notice Emitted when the compliance address is set
   * @param  oldCompliance The old compliance address
   * @param  newCompliance The new compliance address
   */
  event ComplianceSet(address indexed oldCompliance, address indexed newCompliance);

  /// Error emitted when the compliance address is zero
  error ComplianceZeroAddress();

  /**
   * @notice Initialize the contract by setting compliance variable
   *
   * @param  _compliance Address of the compliance contract
   *
   * @dev    Function should be called by the inheriting contract on
   *         initialization
   */
  function __OndoComplianceGMClientInitializable_init(address _compliance)
    internal
    onlyInitializing
  {
    __OndoComplianceGMClientInitializable_init_unchained(_compliance);
  }

  /**
   * @dev Internal function to future-proof parent linearization. Matches OZ
   *      upgradeable suggestions
   */
  function __OndoComplianceGMClientInitializable_init_unchained(address _compliance)
    internal
    onlyInitializing
  {
    _setCompliance(_compliance);
  }

  /**
   * @notice Sets the compliance address for this client
   * @param  _compliance The new compliance address
   */
  function _setCompliance(address _compliance) internal {
    if (_compliance == address(0)) {
      revert ComplianceZeroAddress();
    }
    address oldCompliance = address(compliance);
    compliance = IOndoComplianceGMView(_compliance);
    emit ComplianceSet(oldCompliance, _compliance);
  }

  /**
   * @notice Checks whether an address has been blocked
   * @param  account The account to check
   * @dev    This function will revert if the account is not compliant
   */
  function _checkIsCompliant(address account) internal {
    compliance.checkIsCompliant(account);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[49] private __gap;
}
