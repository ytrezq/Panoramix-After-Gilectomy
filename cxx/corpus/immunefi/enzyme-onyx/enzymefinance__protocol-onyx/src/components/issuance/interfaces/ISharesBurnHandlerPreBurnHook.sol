// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

/// @title ISharesBurnHandlerPreBurnHook Interface
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Hook called by SharesBurnHandler before burning shares
interface ISharesBurnHandlerPreBurnHook {
    /// @param _originator An admin or the owner of the Shares contract executing the burn
    /// @param _from The holder whose shares are burned
    /// @param _sharesAmount The amount of shares to burn
    function preBurn(address _originator, address _from, uint256 _sharesAmount) external;
}
