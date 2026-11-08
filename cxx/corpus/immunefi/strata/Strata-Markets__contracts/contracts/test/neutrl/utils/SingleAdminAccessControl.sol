// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/interfaces/IERC5313.sol";

/**
 * @title SingleAdminAccessControl
 * @notice SingleAdminAccessControl is a contract that provides a single admin role
 * @notice This contract is a simplified alternative to OpenZeppelin's AccessControlDefaultAdminRules
 */
abstract contract SingleAdminAccessControl is IERC5313, AccessControl {
    error InvalidAdminChange();
    error NotPendingAdmin();

    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);
    event AdminTransferRequested(address indexed oldAdmin, address indexed newAdmin);

    address private _currentDefaultAdmin;
    address private _pendingDefaultAdmin;

    modifier notAdmin(bytes32 role) {
        if (role == DEFAULT_ADMIN_ROLE) revert InvalidAdminChange();
        _;
    }

    /// @notice Transfer the admin role to a new address
    /// @notice This can ONLY be executed by the current admin
    /// @param newAdmin address
    function transferAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAdmin == address(0) || newAdmin == _msgSender()) {
            revert InvalidAdminChange();
        }
        _pendingDefaultAdmin = newAdmin;
        emit AdminTransferRequested(_currentDefaultAdmin, newAdmin);
    }

    function acceptAdmin() external {
        if (_msgSender() != _pendingDefaultAdmin) revert NotPendingAdmin();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /// @notice grant a role
    /// @notice can only be executed by the current single admin
    /// @notice admin role cannot be granted externally
    /// @param role bytes32
    /// @param account address
    function grantRole(bytes32 role, address account) public override onlyRole(DEFAULT_ADMIN_ROLE) notAdmin(role) {
        _grantRole(role, account);
    }

    /// @notice revoke a role
    /// @notice can only be executed by the current admin
    /// @notice admin role cannot be revoked
    /// @param role bytes32
    /// @param account address
    function revokeRole(bytes32 role, address account) public override onlyRole(DEFAULT_ADMIN_ROLE) notAdmin(role) {
        _revokeRole(role, account);
    }

    /// @notice renounce the role of _msgSender()
    /// @notice admin role cannot be renounced
    /// @param role bytes32
    /// @param account address
    function renounceRole(bytes32 role, address account) public virtual override notAdmin(role) {
        super.renounceRole(role, account);
    }

    /**
     * @dev See {IERC5313-owner}.
     */
    function owner() external view virtual returns (address) {
        return _currentDefaultAdmin;
    }

    /**
     * @notice no way to change admin without removing old admin first
     */
    function _grantRole(bytes32 role, address account) internal override returns (bool) {
        if (role == DEFAULT_ADMIN_ROLE) {
            emit AdminTransferred(_currentDefaultAdmin, account);
            _revokeRole(DEFAULT_ADMIN_ROLE, _currentDefaultAdmin);
            _currentDefaultAdmin = account;
            delete _pendingDefaultAdmin;
        }
        return super._grantRole(role, account);
    }
}
