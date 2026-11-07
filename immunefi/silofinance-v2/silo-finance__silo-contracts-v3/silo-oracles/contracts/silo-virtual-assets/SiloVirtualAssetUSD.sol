// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract SiloVirtualAssetUSD {
    function name() external pure returns (string memory) {
        return "Silo Virtual Asset - USD";
    }

    function symbol() external pure returns (string memory) {
        return "USD";
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }
}
