// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IDolomiteMargin {
    struct Info {
        address owner;  // The address that owns the account
        uint256 number; // A nonce that allows a single address to control many accounts
    }
    struct Wei {
        bool sign; // true if positive
        uint256 value;
    }
    function getAccountWei(Info calldata account, uint256 marketId) external view returns (Wei memory);
    function getMarketIdByTokenAddress(address token) external view returns (uint256);
}