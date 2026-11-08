// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

/// @title ISharesTransferValidator Interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface ISharesTransferValidator {
    function validateSharesTransfer(address _originator, address _from, address _to, uint256 _amount) external;
}
