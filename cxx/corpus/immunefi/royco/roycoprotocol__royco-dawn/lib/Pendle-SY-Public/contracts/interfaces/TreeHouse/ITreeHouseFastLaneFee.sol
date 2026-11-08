// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface ITreeHouseFastLaneFee {
    function applyFee(uint256 _grossAmount) external view returns (uint256 _feeCharged);
}
