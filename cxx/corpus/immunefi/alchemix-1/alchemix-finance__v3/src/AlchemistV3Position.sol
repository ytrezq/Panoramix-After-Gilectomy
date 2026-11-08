// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IAlchemistV3} from "./interfaces/IAlchemistV3.sol";
import {IMetadataRenderer} from "./interfaces/IMetadataRenderer.sol";

/**
 * @title AlchemistV3Position
 * @notice ERC721 position token for AlchemistV3, where only the AlchemistV3 contract
 *         is allowed to mint and burn tokens. Minting returns a unique token id.
 */
contract AlchemistV3Position is ERC721Enumerable {
    using Strings for uint256;

    /// @notice The only address allowed to mint and burn position tokens.
    address public alchemist;

    /// @notice The admin of the NFT contract, allowed to update the metadata renderer.
    address public admin;

    /// @notice Counter used for generating unique token ids.
    uint256 private _currentTokenId;

    /// @notice The external contract that generates tokenURI metadata.
    address public metadataRenderer;

    /// @notice An error which is used to indicate that the function call failed because the caller is not the alchemist
    error CallerNotAlchemist();

    /// @notice An error which is used to indicate that the function call failed because the caller is not the admin
    error CallerNotAdmin();

    /// @notice An error which is used to indicate that Alchemist set is the zero address
    error AlchemistZeroAddressError();

    /// @notice An error which is used to indicate that address minted to is the zero address
    error MintToZeroAddressError();

    /// @notice An error which is used to indicate that the metadata renderer is not set
    error MetadataRendererNotSet();

    /// @dev Modifier to restrict calls to only the authorized AlchemistV3 contract.
    modifier onlyAlchemist() {
        if (msg.sender != alchemist) {
            revert CallerNotAlchemist();
        }

        _;
    }

    /// @dev Modifier to restrict calls to only the admin.
    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert CallerNotAdmin();
        }

        _;
    }

    /**
     * @notice Constructor that sets the Alchemist address, admin, and initializes the ERC721 token.
     * @param alchemist_ The address of the Alchemist contract.
     * @param admin_ The address of the admin allowed to update the metadata renderer.
     */
    constructor(address alchemist_, address admin_) ERC721("AlchemistV3Position", "ALCV3") {
        if (alchemist_ == address(0)) {
            revert AlchemistZeroAddressError();
        }
        alchemist = alchemist_;
        admin = admin_;
    }

    /// @notice Sets or updates the metadata renderer. Only callable by the admin.
    /// @param renderer The address of the new metadata renderer contract.
    function setMetadataRenderer(address renderer) external onlyAdmin {
        metadataRenderer = renderer;
    }

    /// @notice Transfers admin rights to a new address. Only callable by the current admin.
    /// @param newAdmin The address of the new admin.
    function setAdmin(address newAdmin) external onlyAdmin {
        admin = newAdmin;
    }

    /**
     * @notice Mints a new position NFT to `to`.
     * @dev Only callable by the AlchemistV3 contract.
     * @param to The recipient address for the new position.
     * @return tokenId The unique token id minted.
     */
    function mint(address to) external onlyAlchemist returns (uint256) {
        if (to == address(0)) {
            revert MintToZeroAddressError();
        }
        _currentTokenId++;
        uint256 tokenId = _currentTokenId;
        _mint(to, tokenId);
        return tokenId;
    }

    function burn(uint256 tokenId) public onlyAlchemist {
        _burn(tokenId);
    }

    /**
     * @notice Returns the token URI with embedded SVG
     * @param tokenId The token ID
     * @return The full token URI with data
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        // revert if the token does not exist
        ERC721(address(this)).ownerOf(tokenId);
        if (metadataRenderer == address(0)) {
            revert MetadataRendererNotSet();
        }
        return IMetadataRenderer(metadataRenderer).tokenURI(tokenId);
    }

    /**
     * @notice Override supportsInterface to resolve inheritance conflicts.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @notice Hook that is called before any token transfer
     */
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);
        // Reset mint allowances before the transfer completes
        if (from != address(0)) {
            // Skip during minting
            IAlchemistV3(alchemist).resetMintAllowances(tokenId);
        }
        // Call parent implementation first
        return super._update(to, tokenId, auth);
    }
}
