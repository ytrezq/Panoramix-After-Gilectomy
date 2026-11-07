// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC721Enumerable} from "openzeppelin-contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721} from "openzeppelin-contracts/token/ERC721/ERC721.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import "./INFTDescriptor.sol";

contract LegendsOfMaBeets is ERC721Enumerable, Ownable {
    /// @dev Nonce to use for new relicId.
    uint256 private idNonce;

    error NonExistentToken();

    /// @notice Info of each position.
    struct PositionInfo {
        uint256 amount;
        uint256 level;
    }

    /// @notice The NFT descriptor contract.
    INFTDescriptor public nftDescriptor;

    // /// @notice Info of each og position.
    mapping(uint256 => PositionInfo) private _positionForId;

    /**
     * @dev Constructs and initializes the contract.
     * @param descriptor The NFTDescriptor contract to use for tokenURI.
     */
    constructor(INFTDescriptor descriptor) ERC721("Legends of maBeets", "LOM") Ownable(msg.sender) {
        nftDescriptor = descriptor;
    }

    /**
     * @notice Mints a new NFT to the user with the supplied level and amount.
     * @param to The user address to mint the NFT to.
     * @param level The level of the legacy maBeets position.
     * @param amount The amount of the legacy maBeets position.
     */
    function mint(address to, uint256 level, uint256 amount) public onlyOwner returns (uint256 id) {
        id = _mint(to);
        PositionInfo storage position = _positionForId[id];
        position.amount = amount;
        position.level = level;
    }

    /**
     * @notice Mints many new NFTs.
     * @param to The user addresses to mint the NFT to.
     * @param level The levels of the legacy maBeets position.
     * @param amount The amounts of the legacy maBeets position.
     */
    function mintMany(address[] calldata to, uint256[] calldata level, uint256[] calldata amount) public onlyOwner {
        require(to.length == level.length && to.length == amount.length, "Arrays must be the same length");
        uint256 id = 0;
        for (uint256 i = 0; i < to.length; i++) {
            id = _mint(to[i]);
            _positionForId[id].amount = amount[i];
            _positionForId[id].level = level[i];
        }
    }

    /// @notice Returns a PositionInfo object for the given id.
    function getPositionForId(uint256 id) public view returns (PositionInfo memory position) {
        position = _positionForId[id];
    }

    /**
     * @notice Sets a new NFTDescriptor contract.
     * @param newDescriptor The new contract to be set.
     */
    function setNFTDescriptor(INFTDescriptor newDescriptor) public onlyOwner {
        nftDescriptor = newDescriptor;
    }

    /**
     * @notice Returns the ERC721 tokenURI given by the NFTDescriptor.
     * @dev Can be gas expensive if used in a transaction and the NFTDescriptor is complex.
     * @param tokenId The NFT ID of the position to get the tokenURI for.
     */
    function tokenURI(uint256 tokenId) public view override(ERC721) returns (string memory) {
        PositionInfo memory position = getPositionForId(tokenId);
        if (position.amount == 0) revert NonExistentToken();
        return nftDescriptor.constructTokenURI(position);
    }

    /// @dev Increments the ID nonce and mints a new Relic to `to`.
    function _mint(address to) private returns (uint256 id) {
        id = ++idNonce;
        _safeMint(to, id);
    }
}
