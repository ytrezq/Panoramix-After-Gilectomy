// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IMetadataRenderer} from "./interfaces/IMetadataRenderer.sol";
import {NFTMetadataGenerator} from "./libraries/NFTMetadataGenerator.sol";

/// @title AlchemistV3PositionRenderer
/// @notice Default metadata renderer for AlchemistV3Position NFTs.
contract AlchemistV3PositionRenderer is IMetadataRenderer {
    /// @inheritdoc IMetadataRenderer
    function tokenURI(uint256 tokenId) external pure override returns (string memory) {
        return NFTMetadataGenerator.generateTokenURI(tokenId, "Alchemist V3 Position");
    }
}
