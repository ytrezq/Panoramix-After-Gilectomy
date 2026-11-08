//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IMasterPenpie {
    function multiclaim(address[] calldata _stakingTokens) external;
}