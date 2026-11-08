// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import {Currency} from "../types/Currency.sol";

/// @notice Transient accounting for per-app reserve deficits within a lock.
/// A deficit is created when an app's `reservesOfApp` would underflow mid-lock
/// (e.g. a hook re-enters the app during a callback before the outer operation's
/// delta is booked). The deficit must be fully repaid before the lock ends. It manages:
///  - 0: uint256 deficitCount (number of non-zero (app, currency) deficits)
///  - 1: mapping(address app => mapping(Currency currency => uint256 deficit))
library AppDeficit {
    /// @dev uint256 internal constant DEFICIT_COUNT_SLOT = uint256(keccak256("APP_DEFICIT_COUNT")) - 1;
    uint256 internal constant DEFICIT_COUNT_SLOT = 0x8441ca20eb4e3f4809b32435cc73fbff7fb24d1abccd9553e242325f6e57cdb9;

    /// @dev uint256 internal constant DEFICIT_SLOT = uint256(keccak256("APP_DEFICIT")) - 1;
    uint256 internal constant DEFICIT_SLOT = 0xb15a985351e7fec20c5ab24bbbbeccb6443ba2a83f05cd1411825d064d91cf43;

    /// @notice Get the count of (app, currency) pairs with a non-zero deficit
    /// @return c The count of non-zero deficits
    function count() internal view returns (uint256 c) {
        assembly ("memory-safe") {
            c := tload(DEFICIT_COUNT_SLOT)
        }
    }

    /// @notice Get the current deficit for a given app and currency
    /// @param app The app whose reserves are in deficit
    /// @param currency The currency of the deficit
    /// @return deficit The deficit amount
    function getDeficit(address app, Currency currency) internal view returns (uint256 deficit) {
        uint256 elementSlot = uint256(keccak256(abi.encode(app, currency, DEFICIT_SLOT)));
        assembly ("memory-safe") {
            deficit := tload(elementSlot)
        }
    }

    /// @notice Record an additional deficit for an app and currency
    /// if the deficit goes from zero to non-zero then increment the count of non-zero deficits
    /// @param app The app whose reserves are in deficit
    /// @param currency The currency of the deficit
    /// @param amount The deficit to be added to the existing deficit
    function add(address app, Currency currency, uint256 amount) internal {
        if (amount == 0) return;

        uint256 elementSlot = uint256(keccak256(abi.encode(app, currency, DEFICIT_SLOT)));
        uint256 current;
        assembly ("memory-safe") {
            current := tload(elementSlot)
        }
        if (current == 0) {
            assembly ("memory-safe") {
                tstore(DEFICIT_COUNT_SLOT, add(tload(DEFICIT_COUNT_SLOT), 1))
            }
        }
        /// @dev checked addition: an app's aggregated deficit must never wrap
        uint256 next = current + amount;
        assembly ("memory-safe") {
            tstore(elementSlot, next)
        }
    }

    /// @notice Repay an app's deficit with `amount`, returning whatever is left over
    /// if the deficit goes from non-zero to zero then decrement the count of non-zero deficits
    /// @dev fast path: when no deficit exists anywhere, a single tload and `amount` is returned untouched
    /// @param app The app whose deficit is being repaid
    /// @param currency The currency of the deficit
    /// @param amount The amount available for repayment
    /// @return remaining The portion of `amount` left after the deficit is repaid
    function repay(address app, Currency currency, uint256 amount) internal returns (uint256 remaining) {
        if (count() == 0) return amount;

        uint256 elementSlot = uint256(keccak256(abi.encode(app, currency, DEFICIT_SLOT)));
        uint256 current;
        assembly ("memory-safe") {
            current := tload(elementSlot)
        }
        if (current == 0) return amount;

        unchecked {
            if (amount >= current) {
                remaining = amount - current;
                assembly ("memory-safe") {
                    tstore(elementSlot, 0)
                    tstore(DEFICIT_COUNT_SLOT, sub(tload(DEFICIT_COUNT_SLOT), 1))
                }
            } else {
                // remaining stays 0, deficit partially repaid
                uint256 next = current - amount;
                assembly ("memory-safe") {
                    tstore(elementSlot, next)
                }
            }
        }
    }
}
