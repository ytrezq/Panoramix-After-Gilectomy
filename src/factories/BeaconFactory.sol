// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {GlobalOwnable} from "src/global/utils/GlobalOwnable.sol";
import {DeploymentHelpersLib} from "src/utils/DeploymentHelpersLib.sol";

/// @title BeaconFactory Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A factory contract for deploying beacon proxy instances
contract BeaconFactory is IBeacon, GlobalOwnable {
    //==================================================================================================================
    // State
    //==================================================================================================================

    address public override implementation;
    mapping(address _who => bool) public isInstance;
    uint256 internal nonce;

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event ImplementationSet(address implementation);

    event ProxyDeployed(address proxy);

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor(address _global) GlobalOwnable(_global) {}

    //==================================================================================================================
    // Config (access: owner)
    //==================================================================================================================

    function setImplementation(address _implementation) external onlyOwner {
        implementation = _implementation;

        emit ImplementationSet(_implementation);
    }

    //==================================================================================================================
    // Functions
    //==================================================================================================================

    function deployProxy(bytes calldata _initData) external returns (address proxy_) {
        bytes memory bytecode = abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(address(this), _initData));

        proxy_ = DeploymentHelpersLib.deployAtUniqueAddress({_bytecode: bytecode, _nonce: nonce++});

        isInstance[proxy_] = true;

        emit ProxyDeployed({proxy: proxy_});
    }
}
