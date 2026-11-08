// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IDSServiceConsumer} from "./IDSServiceConsumer.sol";

interface IDSToken is IDSServiceConsumer {
    function issueTokens(address to, uint256 amount) external;
    function burn(address from, uint256 amount, string calldata reason) external;
}
