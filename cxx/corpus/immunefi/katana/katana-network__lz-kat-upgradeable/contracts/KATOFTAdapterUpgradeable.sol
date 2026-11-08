// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { KATOFTAdapterStorageLayout } from "./KATOFTAdapterStorageLayout.sol";
import { OFTAdapterUpgradeable } from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTAdapterUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract KATOFTAdapterUpgradeable is KATOFTAdapterStorageLayout, OFTAdapterUpgradeable, AccessControlUpgradeable {
    constructor(address _token, address _lzEndpoint) OFTAdapterUpgradeable(_token, _lzEndpoint) {
        _disableInitializers();
    }

    function initialize(address _delegate) public initializer {
        __Ownable_init(_delegate);

        // access control not needed, but keeping it for upgrade compatibility
        __AccessControl_init();

        __OFTAdapter_init(_delegate);
    }
}
