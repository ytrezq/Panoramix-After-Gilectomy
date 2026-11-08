// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {OFTUpgradeable} from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTUpgradeable.sol";

/**
 * @title KATOFTMintable
 * @notice Test helper that exposes mint function for testing
 * @dev This is a simplified OFT without pausable for testing purposes
 */
contract KATOFTMintable is OFTUpgradeable {
    constructor(address _endpoint) OFTUpgradeable(_endpoint) {
        _disableInitializers();
    }

    function initialize(string memory _name, string memory _symbol, address _delegate) public initializer {
        __OFT_init(_name, _symbol, _delegate);
        __Ownable_init(_delegate);
    }

    /**
     * @notice Mint tokens for testing
     * @param to Address to mint to
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

