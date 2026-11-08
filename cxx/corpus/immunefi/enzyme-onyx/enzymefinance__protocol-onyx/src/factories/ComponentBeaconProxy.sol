// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IComponentProxy} from "src/interfaces/IComponentProxy.sol";

/// @title ComponentBeaconProxy Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice BeaconProxy for use with a specified Onyx Shares instance
contract ComponentBeaconProxy is IComponentProxy, BeaconProxy {
    receive() external payable {}

    address public immutable override SHARES;

    constructor(address _beacon, bytes memory _data, address _shares) payable BeaconProxy(_beacon, _data) {
        SHARES = _shares;
    }
}
