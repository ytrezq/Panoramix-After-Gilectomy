// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ISubcompressor} from "./ISubcompressor.sol";

interface IRWAFactorySubcompressor is ISubcompressor {
    function getFactoryData(address factory) external view returns (bytes memory);
    function getInvestorData(address investor, address factory) external view returns (bytes memory);
    function getCreditAccountData(address creditAccount, address factory) external view returns (bytes memory);
}
