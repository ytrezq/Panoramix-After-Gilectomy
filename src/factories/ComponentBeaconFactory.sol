// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {ComponentBeaconProxy} from "src/factories/ComponentBeaconProxy.sol";
import {GlobalOwnable} from "src/global/utils/GlobalOwnable.sol";
import {DeploymentHelpersLib} from "src/utils/DeploymentHelpersLib.sol";

/// @title ComponentBeaconFactory Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A factory contract for deploying beacon proxy instances of Shares components
contract ComponentBeaconFactory is IBeacon, GlobalOwnable {
    //==================================================================================================================
    // State
    //==================================================================================================================

    address public override implementation;
    mapping(address => address) internal instanceToShares;
    uint256 internal nonce;

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event ImplementationSet(address implementation);

    event ProxyDeployed(address proxy, address shares);

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

    function deployProxy(address _shares, bytes calldata _initData) external returns (address proxy_) {
        bytes memory bytecode =
            abi.encodePacked(type(ComponentBeaconProxy).creationCode, abi.encode(address(this), _initData, _shares));

        proxy_ = DeploymentHelpersLib.deployAtUniqueAddress({_bytecode: bytecode, _nonce: nonce++});

        instanceToShares[proxy_] = _shares;

        emit ProxyDeployed({proxy: proxy_, shares: _shares});
    }

    //==================================================================================================================
    // State getters
    //==================================================================================================================

    /// @dev Serves as `isInstance()`
    function getSharesForInstance(address _instance) external view returns (address shares_) {
        return instanceToShares[_instance];
    }
}
