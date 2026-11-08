// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Strings} from "openzeppelin-contracts/utils/Strings.sol";
import "./INFTDescriptor.sol";
import "./LegendsOfMaBeets.sol";

contract NftDescriptor is INFTDescriptor {
    using Strings for uint256;

    string private constant S3 = "https://beethoven-assets.s3.eu-central-1.amazonaws.com/";

    LegendsOfMaBeets public immutable legendsContract;

    constructor() {}

    /// @notice Returns a link to the stored image
    function constructTokenURI(LegendsOfMaBeets.PositionInfo calldata position)
        external
        view
        override
        returns (string memory uri)
    {
        uri = string.concat(S3, "mabeets-legends.png");
    }
}
