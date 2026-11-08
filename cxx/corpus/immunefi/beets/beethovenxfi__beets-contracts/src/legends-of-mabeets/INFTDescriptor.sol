// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./LegendsOfMaBeets.sol";

interface INFTDescriptor {
    function constructTokenURI(LegendsOfMaBeets.PositionInfo calldata position) external view returns (string memory);
}
