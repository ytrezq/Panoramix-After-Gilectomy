// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.8;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC6372Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC6372Upgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

contract ERC20ClockMock is ERC20, IERC6372Upgradeable, IVotesUpgradeable {
    bool timestampBased;

    constructor(bool _timestampBased) ERC20("Name", "TKN") {
        timestampBased = _timestampBased;
    }

    function clock() external view override returns (uint48) {
        if (timestampBased) return uint48(block.timestamp);
        return uint48(block.number);
    }

    function CLOCK_MODE() external view override returns (string memory) {
        if (timestampBased) return "mode=timestamp";
        return "mode=blocknumber&from=default";
    }

    function balanceOf(address) public pure override returns (uint256) {
        return 55555555555;
    }

    function getVotes(address) external pure override returns (uint256) {
        return 55555555555;
    }

    function getPastVotes(address, uint256) external pure override returns (uint256) {
        return 55555555555;
    }

    function getPastTotalSupply(uint256) external pure override returns (uint256) {
        return 55555555555;
    }

    function delegates(address) external pure override returns (address) {}

    function delegate(address delegatee) external override {}

    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        external
        override
    {}
}

contract ERC20NoClockMock is ERC20, IVotesUpgradeable {
    constructor() ERC20("Name", "TKN") {}

    function balanceOf(address) public pure override returns (uint256) {
        return 55555555555;
    }

    function getVotes(address) external pure override returns (uint256) {
        return 55555555555;
    }

    function getPastVotes(address, uint256) external pure override returns (uint256) {
        return 55555555555;
    }

    function getPastTotalSupply(uint256) external pure override returns (uint256) {
        return 55555555555;
    }

    function delegates(address) external pure override returns (address) {}

    function delegate(address delegatee) external override {}

    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        external
        override
    {}
}
