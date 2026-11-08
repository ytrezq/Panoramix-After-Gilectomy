// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTUpgradeable } from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract KATOFTUpgradeable is OFTUpgradeable, PausableUpgradeable {
    constructor(address _lzEndpoint) OFTUpgradeable(_lzEndpoint) {
        _disableInitializers();
    }

    function initialize(string memory _name, string memory _symbol, address _delegate) public initializer {
        __Ownable_init(_delegate);
        __OFT_init(_name, _symbol, _delegate);
        __Pausable_init();
    }
}
