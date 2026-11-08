// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Test } from "@forge-std/Test.sol";

abstract contract Utils is Test {
    uint256 internal constant BLOCK_TIME = 12;

    uint8 internal constant OFT_SHARED_DECIMALS = 6;
    uint8 internal constant PRINCIPAL_TOKEN_DECIMALS = 18;

    /// @notice bound the amount between min and max and return it as OFT compliant amount.
    /// @dev OFT standard has 6 sharedDecimals that is used to implicit cap on the amount of tokens.
    /// The OFT will then remove the dust from the amount that is sent and compare it to the expected amount received.
    /// If both amounts are not equal, the transaction will revert.
    /// cf. https://docs.layerzero.network/v2/developers/evm/oft/quickstart#token-transfer-precision
    function _boundBridgeAmount(uint256 amount, uint256 min, uint256 max) internal pure returns (uint256) {
        return _serializeAmountForOFT(bound(amount, min, max));
    }

    /// @dev Bounds the fuzzing input to a realistic number of blocks.
    function _boundBlocks(uint256 blocks) internal pure returns (uint256) {
        return bound(blocks, 1, type(uint32).max);
    }

    /// @dev Bounds a `uint16` number.
    function _boundUint16(uint16 x, uint16 min, uint16 max) internal pure returns (uint16) {
        return uint16(_bound(uint256(x), uint256(min), uint256(max)));
    }

    /// @dev Rolls & warps the given number of time forward the blockchain.
    function _forwardByTimestamp(uint256 timestamp) internal {
        vm.warp(uint64(block.timestamp) + timestamp);
        vm.roll(block.number + timestamp / BLOCK_TIME);
    }

    /// @dev Rolls & warps the given number of block forward the blockchain.
    function _forward(uint256 blocks) internal {
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + blocks * BLOCK_TIME); // Block speed should depend on test network.
    }

    /// @dev Serializes the given amount to the OFT standard by removing dust.
    function _serializeAmountForOFT(uint256 amount) internal pure returns (uint256) {
        return
            _scaleAmountToDecimals(
                _scaleAmountToDecimals(amount, PRINCIPAL_TOKEN_DECIMALS, OFT_SHARED_DECIMALS),
                OFT_SHARED_DECIMALS,
                PRINCIPAL_TOKEN_DECIMALS
            );
    }

    /// @dev Scales the given amount to the given number of decimals.
    function _scaleAmountToDecimals(
        uint256 amount,
        uint8 fromDecimals,
        uint8 toDecimals
    ) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return amount;
        }
        if (fromDecimals > toDecimals) {
            return amount / (10 ** (fromDecimals - toDecimals));
        }
        return amount * (10 ** (toDecimals - fromDecimals));
    }
}
