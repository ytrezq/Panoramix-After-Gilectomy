// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {
  IIssuanceHours
} from "contracts/globalMarkets/tokenManager/issuanceHours/IIssuanceHours.sol";

/**
 * @title  IssuanceHoursAlwaysOpen
 * @author Ondo Finance
 * @notice Stub implementation of IIssuanceHours that allows 24/7 trading.
 */
contract IssuanceHoursAlwaysOpen is IIssuanceHours {
  /// @notice No-op: always valid, enabling 24/7 issuance.
  function checkIsValidHours() external pure override {
    // intentionally empty — all hours are valid
  }
}
