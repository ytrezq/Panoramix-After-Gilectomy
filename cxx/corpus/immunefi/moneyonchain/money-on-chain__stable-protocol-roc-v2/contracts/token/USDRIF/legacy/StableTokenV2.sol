//////////////////////////////////////////////
//////////////////  WARNING //////////////////
//////////////////////////////////////////////
// THIS CONTRACT IS THE LIVE VERSION OF
// USDRIF AND IT WILL REPLACED WITH AN UPGRADE.
// WE ARE USING IT HERE TO VERIFY THE STORAGE
// COMPATIBILITY WITH THAT NEW VERSION.
//////////////////////////////////////////////
//////////////////////////////////////////////

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./MocRC20.sol";
// Import to allow compilation and deploy of ERC1967Proxy
import "@openzeppelin-v4.8.0/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract StableTokenV2_Legacy is MocRC20 {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
}
