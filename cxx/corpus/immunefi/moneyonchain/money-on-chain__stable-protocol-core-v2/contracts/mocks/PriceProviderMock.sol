// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { IPriceProvider } from "../interfaces/IPriceProvider.sol";

contract PriceProviderMock is IPriceProvider {
    bytes32 public mocPrice;
    bool public has;
    bool public useLastPublicationBlock = false;
    uint256 public lastPublicationBlock = 0;

    /**
     * @notice constructor
     * @param price_ MoC price for mock contract
     */
    constructor(uint256 price_) {
        mocPrice = bytes32(price_);
        has = true;
    }

    function peek() external view returns (bytes32, bool) {
        return (mocPrice, has);
    }

    function poke(uint256 price_) external {
        mocPrice = bytes32(price_);
        lastPublicationBlock = block.number;
    }

    function deprecatePriceProvider() external {
        has = false;
    }

    function restorePriceProvider() external {
        has = true;
    }

    function getLastPublicationBlock() external view returns (uint256) {
        if (useLastPublicationBlock) return lastPublicationBlock;
        else return block.number;
    }

    function setLastPublicationBlock(uint256 lastPublicationBlock_) external returns (uint256) {
        useLastPublicationBlock = true;
        lastPublicationBlock = lastPublicationBlock_;
    }

    function removeLastPublicationBlock() external {
        useLastPublicationBlock = false;
    }
}
