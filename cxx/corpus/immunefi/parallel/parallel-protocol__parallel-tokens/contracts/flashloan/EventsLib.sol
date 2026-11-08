// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";


/// @title FlashLoan_EventsLib
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice Library exposing all events link to the FlashLoan contract.
library FlashLoan_EventsLib {
    /// @notice Event emitted when a flash loan is taken.   
    /// @param token The address of the token borrowed.
    /// @param amount The amount flash loaned.
    /// @param receiver The address of the receiver of the flash loan.
    event FlashLoan(address token, uint256 amount, IERC3156FlashBorrower receiver);

    /// @notice Event emitted when the parameters of a flash loan are updated.
    /// @param token The address of the token borrowed.
    /// @param feesRate The flash loan fee (in basic point).
    /// @param maxBorrowable The maximum amount borrowable.
    /// @param isActive The activation status of the flash loan.
    event FlashLoanParametersUpdated(address token, uint16 feesRate, uint256 maxBorrowable, bool isActive);

    /// @notice Event emitted when the activation status of a token is toggled.
    /// @param token The address of the token borrowed.
    /// @param isActive The activation status of the flash loan.
    event ActiveTokenToggled(address token, bool isActive);

    /// @notice Event emitted when the flash loan fee recipient is updated.
    /// @param newFlashLoanFeeRecipient The new flash loan fee recipient.
    event FlashLoanFeeRecipientUpdated(address newFlashLoanFeeRecipient);

}
