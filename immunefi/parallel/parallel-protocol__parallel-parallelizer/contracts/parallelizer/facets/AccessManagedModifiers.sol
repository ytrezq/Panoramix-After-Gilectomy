// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { LibDiamond } from "../libraries/LibDiamond.sol";
import { LibStorage as s, ParallelizerStorage } from "../libraries/LibStorage.sol";
import "../../utils/Errors.sol";
import "../../utils/Constants.sol";

/// @title AccessManagedModifiers
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @dev This contract is an authorized fork of Angle's `AccessControlModifiers` contract
/// https://github.com/AngleProtocol/angle-transmuter/blob/main/contracts/transmuter/facets/AccessControlModifiers.sol
/// update access logic to use OpenZeppelin's `AccessManaged` logic
contract AccessManagedModifiers {
  /// @notice Checks whether the `msg.sender` can call a function with a given selector
  modifier restricted() {
    if (!LibDiamond.checkCanCall(msg.sender, msg.data)) revert AccessManagedUnauthorized(msg.sender);
    _;
  }

  /// @notice Prevents a contract from calling itself, directly or indirectly
  /// @dev This implementation is an adaptation of the OpenZepellin `ReentrancyGuard` for the purpose of this
  /// Diamond Proxy system. The base implementation can be found here
  /// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol
  modifier nonReentrant() {
    ParallelizerStorage storage ts = s.transmuterStorage();
    // Reentrant protection
    // On the first call, `ts.statusReentrant` will be `NOT_ENTERED`
    if (ts.statusReentrant == ENTERED) revert ReentrantCall();
    // Any calls to the `nonReentrant` modifier after this point will fail
    ts.statusReentrant = ENTERED;

    _;

    // By storing the original value once again, a refund is triggered (see
    // https://eips.ethereum.org/EIPS/eip-2200)
    ts.statusReentrant = NOT_ENTERED;
  }
}
