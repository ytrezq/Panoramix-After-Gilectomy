// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import {IDegenNFT} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IDegenNFT.sol";
import {ICreditFacadeV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";

import {IContractsRegister} from "../interfaces/IContractsRegister.sol";
import {IMarketConfigurator} from "../interfaces/IMarketConfigurator.sol";

contract DefaultDegenNFT is ERC721, IDegenNFT {
    uint256 public constant override version = 3_10;
    bytes32 public constant override contractType = "DEGEN_NFT::DEFAULT";

    address public immutable marketConfigurator;
    address public immutable contractsRegister;
    address public minter;

    uint256 public totalSupply;

    string public baseURI;

    event SetMinter(address indexed newMinter);

    error CallerIsNotAdminException(address caller);
    error CallerIsNotCreditFacadeOrEmergencyAdminException(address caller);
    error CallerIsNotMinterException(address caller);
    error NotImplementedException();

    modifier onlyAdmin() {
        _ensureCallerIsAdmin();
        _;
    }

    modifier onlyMinter() {
        _ensureCallerIsMinter();
        _;
    }

    modifier onlyCreditFacadeOrEmergencyAdmin() {
        _ensureCallerIsCreditFacadeOrEmergencyAdmin();
        _;
    }

    constructor(address marketConfigurator_, string memory name_, string memory symbol_) ERC721(name_, symbol_) {
        marketConfigurator = marketConfigurator_;
        contractsRegister = IMarketConfigurator(marketConfigurator_).contractsRegister();
    }

    function serialize() external view override returns (bytes memory) {
        return abi.encode(marketConfigurator, minter, name(), symbol(), baseURI, totalSupply);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        return _baseURI();
    }

    function mint(address to, uint256 amount) external onlyMinter {
        uint256 balanceBefore = balanceOf(to);

        for (uint256 i = 0; i < amount; ++i) {
            uint256 tokenId = (uint256(uint160(to)) << 40) + balanceBefore + i;
            _mint(to, tokenId);
        }

        totalSupply += amount;
    }

    function burn(address from, uint256 amount) external override onlyCreditFacadeOrEmergencyAdmin {
        uint256 balance = balanceOf(from);

        for (uint256 i = 0; i < amount; ++i) {
            uint256 tokenId = (uint256(uint160(from)) << 40) + balance - i - 1;
            _burn(tokenId);
        }

        totalSupply -= amount;
    }

    function approve(address, uint256) public pure virtual override {
        revert NotImplementedException();
    }

    function setApprovalForAll(address, bool) public pure virtual override {
        revert NotImplementedException();
    }

    function transferFrom(address, address, uint256) public pure virtual override {
        revert NotImplementedException();
    }

    function safeTransferFrom(address, address, uint256) public pure virtual override {
        revert NotImplementedException();
    }

    function safeTransferFrom(address, address, uint256, bytes memory) public pure virtual override {
        revert NotImplementedException();
    }

    function setMinter(address newMinter) external onlyAdmin {
        if (newMinter == minter) return;
        minter = newMinter;
        emit SetMinter(newMinter);
    }

    function setBaseUri(string calldata baseURI_) external onlyAdmin {
        baseURI = baseURI_;
    }

    function _ensureCallerIsAdmin() internal view {
        if (msg.sender != IMarketConfigurator(marketConfigurator).admin()) revert CallerIsNotAdminException(msg.sender);
    }

    function _ensureCallerIsCreditFacadeOrEmergencyAdmin() internal view {
        if (msg.sender != IMarketConfigurator(marketConfigurator).emergencyAdmin() && !_callerIsCreditFacade()) {
            revert CallerIsNotCreditFacadeOrEmergencyAdminException(msg.sender);
        }
    }

    function _callerIsCreditFacade() internal view returns (bool) {
        address creditManager = ICreditFacadeV3(msg.sender).creditManager();
        if (
            ICreditManagerV3(creditManager).creditFacade() != msg.sender
                || !IContractsRegister(contractsRegister).isCreditManager(creditManager)
        ) return false;

        return true;
    }

    function _ensureCallerIsMinter() internal view {
        if (msg.sender != minter) revert CallerIsNotMinterException(msg.sender);
    }
}
