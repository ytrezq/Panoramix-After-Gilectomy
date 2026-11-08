// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IMetadataRenderer {
    /// @notice Generate the token URI for the given token ID.
    /// @param tokenId The token ID.
    /// @return The full token URI with data.
    function tokenURI(uint256 tokenId) external view returns (string memory);
}
