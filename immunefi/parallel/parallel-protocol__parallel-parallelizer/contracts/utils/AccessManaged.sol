// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { AuthorityUtils } from "@openzeppelin/contracts/access/manager/AuthorityUtils.sol";
import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";

import "../utils/Errors.sol";

/// @title AccessControl
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @dev Fork of OpenZeppelin's `AccessManaged` contract
/// updated to make _checkCanCall to return bool
/// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/manager/AccessManaged.sol
contract AccessManaged is Context, IAccessManaged {
  address private _authority;

  bool private _consumingSchedule;

  /**
   * @dev Initializes the contract connected to an initial authority.
   */
  constructor(address initialAuthority) {
    _setAuthority(initialAuthority);
  }

  /**
   * @dev Restricts access to a function as defined by the connected Authority for this contract and the
   * caller and selector of the function that entered the contract.
   *
   * [IMPORTANT]
   * ====
   * In general, this modifier should only be used on `external` functions. It is okay to use it on `public`
   * functions that are used as external entry points and are not called internally. Unless you know what you're
   * doing, it should never be used on `internal` functions. Failure to follow these rules can have critical security
   * implications! This is because the permissions are determined by the function that entered the contract, i.e. the
   * function at the bottom of the call stack, and not the function where the modifier is visible in the source code.
   * ====
   *
   * [WARNING]
   * ====
   * Avoid adding this modifier to the
   * https://docs.soliditylang.org/en/v0.8.20/contracts.html#receive-ether-function[`receive()`]
   * function or the https://docs.soliditylang.org/en/v0.8.20/contracts.html#fallback-function[`fallback()`]. These
   * functions are the only execution paths where a function selector cannot be unambiguously determined from the
   * calldata
   * since the selector defaults to `0x00000000` in the `receive()` function and similarly in the `fallback()`
   * function
   * if no calldata is provided. (See {_checkCanCall}).
   *
   * The `receive()` function will always panic whereas the `fallback()` may panic depending on the calldata length.
   * ====
   */
  modifier restricted() {
    address caller = _msgSender();
    require(_checkCanCall(caller, _msgData()), AccessManagedUnauthorized(caller));
    _;
  }

  /// @inheritdoc IAccessManaged
  function authority() public view virtual returns (address) {
    return _authority;
  }

  /// @inheritdoc IAccessManaged
  function setAuthority(address newAuthority) public virtual {
    address caller = _msgSender();
    if (caller != authority()) {
      revert AccessManagedUnauthorized(caller);
    }
    if (newAuthority.code.length == 0) {
      revert AccessManagedInvalidAuthority(newAuthority);
    }
    _setAuthority(newAuthority);
  }

  /// @inheritdoc IAccessManaged
  function isConsumingScheduledOp() public view returns (bytes4) {
    return _consumingSchedule ? this.isConsumingScheduledOp.selector : bytes4(0);
  }

  /**
   * @dev Transfers control to a new authority. Internal function with no access restriction. Allows bypassing the
   * permissions set by the current authority.
   */
  function _setAuthority(address newAuthority) internal virtual {
    _authority = newAuthority;
    emit AuthorityUpdated(newAuthority);
  }

  function _checkCanCall(address caller, bytes calldata data) internal virtual returns (bool) {
    (bool immediate, uint32 delay) =
      AuthorityUtils.canCallWithDelay(authority(), caller, address(this), bytes4(data[0:4]));
    if (!immediate) {
      if (delay > 0) {
        _consumingSchedule = true;
        IAccessManager(authority()).consumeScheduledOp(caller, data);
        _consumingSchedule = false;
      } else {
        return false;
      }
    }
    return true;
  }
}
