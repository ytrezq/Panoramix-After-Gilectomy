// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

/// @title ISharesMintHandlerPreMintHook Interface
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Hook called by SharesMintHandler before minting shares
interface ISharesMintHandlerPreMintHook {
    /// @param _originator An admin or the owner of the Shares contract executing the mint
    /// @param _to The recipient of the minted shares
    /// @param _sharesAmount The amount of shares to mint
    function preMint(address _originator, address _to, uint256 _sharesAmount) external;
}
