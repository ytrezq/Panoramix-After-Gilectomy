// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract SiloVirtualAssetEUR {
    function name() external pure returns (string memory) {
        return "Silo Virtual Asset - EUR";
    }

    function symbol() external pure returns (string memory) {
        return "EUR";
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }
}
