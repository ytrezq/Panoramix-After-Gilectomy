// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract SiloVirtualAssetBTC {
    function name() external pure returns (string memory) {
        return "Silo Virtual Asset - BTC";
    }

    function symbol() external pure returns (string memory) {
        return "BTC";
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }
}
