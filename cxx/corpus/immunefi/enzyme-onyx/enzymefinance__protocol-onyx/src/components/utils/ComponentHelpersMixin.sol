// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IComponentProxy} from "src/interfaces/IComponentProxy.sol";
import {Shares} from "src/shares/Shares.sol";

/// @title ComponentHelpersMixin Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Mixin of helpers for IComponentProxy implementations
abstract contract ComponentHelpersMixin {
    error ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized();
    error ComponentHelpersMixin__OnlyShares__Unauthorized();

    modifier onlyAdminOrOwner() {
        require(__isAdminOrOwner(msg.sender), ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized());
        _;
    }

    modifier onlyShares() {
        require(msg.sender == __getShares(), ComponentHelpersMixin__OnlyShares__Unauthorized());
        _;
    }

    function __getShares() internal view returns (address) {
        return IComponentProxy(address(this)).SHARES();
    }

    function __isAdminOrOwner(address _who) internal view returns (bool) {
        return Shares(__getShares()).isAdminOrOwner(_who);
    }
}
