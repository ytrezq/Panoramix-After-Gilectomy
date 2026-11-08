// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IStateSerializer} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IStateSerializer.sol";
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

/// @title  RWA factory interface
/// @author Gearbox Foundation
/// @notice Generic interface for a contract that can be used to open and manage RWA-compliant credit accounts
/// @dev    Implementations must have type `RWA_FACTORY::{POSTFIX}`
interface IRWAFactory is IVersion, IStateSerializer {
    // ------ //
    // EVENTS //
    // ------ //

    event OpenRWACreditAccount(address indexed creditAccount, address indexed wallet, address indexed investor);
    event SetCreditAccountFrozenStatus(address indexed creditAccount, bool frozen);
    event TransferCreditAccount(
        address indexed creditAccount, address indexed oldInvestor, address indexed newInvestor
    );

    // ------ //
    // ERRORS //
    // ------ //

    error CallerIsNotInvestorException(address caller, address creditAccount);
    error FrozenCreditAccountException(address creditAccount);
    error UnknownCreditAccountException(address creditAccount);

    // ------- //
    // GETTERS //
    // ------- //

    function getTokens() external view returns (address[] memory);
    function isCreditAccount(address creditAccount) external view returns (bool);
    function getCreditAccounts(address investor) external view returns (address[] memory);
    function getInvestor(address creditAccount) external view returns (address);
    function getWallet(address creditAccount) external view returns (address);
    function isFrozen(address creditAccount) external view returns (bool);

    // ------------- //
    // ADMIN ACTIONS //
    // ------------- //

    function setCreditAccountFrozenStatus(address creditAccount, bool frozen) external;
    function setAllCreditAccountsFrozenStatus(address investor, bool frozen) external;
    function setAllCreditAccountsFrozenStatus(address creditManager, address investor, bool frozen) external;

    function transferCreditAccount(address creditAccount, address newInvestor) external;
    function transferAllCreditAccounts(address investor, address newInvestor) external;
    function transferAllCreditAccounts(address creditManager, address investor, address newInvestor) external;
}
