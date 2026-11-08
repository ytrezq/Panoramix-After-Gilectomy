// SPDX-License-Identifier: BUSL-1.1
/*
      ▄▄█████████▄
   ╓██▀└ ,╓▄▄▄, '▀██▄
  ██▀ ▄██▀▀╙╙▀▀██▄ └██µ           ,,       ,,      ,     ,,,            ,,,
 ██ ,██¬ ▄████▄  ▀█▄ ╙█▄      ▄███▀▀███▄   ███▄    ██  ███▀▀▀███▄    ▄███▀▀███,
██  ██ ╒█▀'   ╙█▌ ╙█▌ ██     ▐██      ███  █████,  ██  ██▌    └██▌  ██▌     └██▌
██ ▐█▌ ██      ╟█  █▌ ╟█     ██▌      ▐██  ██ └███ ██  ██▌     ╟██ j██       ╟██
╟█  ██ ╙██    ▄█▀ ▐█▌ ██     ╙██      ██▌  ██   ╙████  ██▌    ▄██▀  ██▌     ,██▀
 ██ "██, ╙▀▀███████████⌐      ╙████████▀   ██     ╙██  ███████▀▀     ╙███████▀`
  ██▄ ╙▀██▄▄▄▄▄,,,                ¬─                                    '─¬
   ╙▀██▄ '╙╙╙▀▀▀▀▀▀▀▀
      ╙▀▀██████R⌐
 */
pragma solidity 0.8.33;

import {IOndoCompliance} from "contracts/xManager/interfaces/IOndoCompliance.sol";
import {
  IOndoComplianceGMView
} from "contracts/globalMarkets/gmTokenCompliance/IOndoComplianceGMView.sol";
import {Ownable2Step} from "contracts/external/openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title  OndoComplianceGMView
 * @author Ondo Finance
 * @notice The OndoComplianceGMView contract is a read-only view of the OndoCompliance contract.
 * @dev    This contracts exist to consolidate all GM Tokens under one address allowing for
 *         ease of future changes in the compliance implementation and backwards compatibility
 *         with existing systems. All GM compliance clients should point to this contract rather
 *         than going directly to OndoCompliance.
 */
contract OndoComplianceGMView is IOndoComplianceGMView, Ownable2Step {
  /// The OndoCompliance contract
  IOndoCompliance public compliance;

  /// The address used to denote all GM tokens
  address public gmIdentifier =
    address(uint160(uint256(keccak256(abi.encodePacked("global_markets")))));

  /**
   * @notice Emitted when the OndoCompliance contract address is set
   * @param  oldCompliance The old OndoCompliance contract address
   * @param  newCompliance The new OndoCompliance contract address
   */
  event ComplianceSet(address indexed oldCompliance, address indexed newCompliance);

  /**
   * @notice Emitted when the GM identifier is set
   * @param  oldGMIdentifier The old GM identifier
   * @param  newGMIdentifier The new GM identifier
   */
  event GMIdentifierSet(address indexed oldGMIdentifier, address indexed newGMIdentifier);

  /// Error emitted when attempting to set the compliance address to zero
  error ComplianceAddressCannotBeZero();

  /// Error emitted when attempting to set the GM identifier to zero
  error GMIdentifierCannotBeZero();

  /**
   * @param _ondoCompliance The address of the OndoCompliance contract
   */
  constructor(address _ondoCompliance) {
    if (_ondoCompliance == address(0)) {
      revert ComplianceAddressCannotBeZero();
    }
    _transferOwnership(msg.sender);
    compliance = IOndoCompliance(_ondoCompliance);
  }

  /**
   * @notice Checks if a user is compliant with the GM token standards
   * @param  user The address of the user to check
   */
  function checkIsCompliant(address user) external override {
    compliance.checkIsCompliant(gmIdentifier, user);
  }

  /**
   * @notice Sets the compliance address OndoCompliance contract
   * @param  _compliance The address of the new compliance contract
   */
  function setCompliance(address _compliance) external onlyOwner {
    if (_compliance == address(0)) {
      revert ComplianceAddressCannotBeZero();
    }
    emit ComplianceSet(address(compliance), _compliance);
    compliance = IOndoCompliance(_compliance);
  }

  /**
   * @notice Sets the GM identifier address
   * @param  _gmIdentifier The new GM identifier address
   */
  function setGMIdentifier(address _gmIdentifier) external onlyOwner {
    if (_gmIdentifier == address(0)) {
      revert GMIdentifierCannotBeZero();
    }
    emit GMIdentifierSet(gmIdentifier, _gmIdentifier);
    gmIdentifier = _gmIdentifier;
  }
}
