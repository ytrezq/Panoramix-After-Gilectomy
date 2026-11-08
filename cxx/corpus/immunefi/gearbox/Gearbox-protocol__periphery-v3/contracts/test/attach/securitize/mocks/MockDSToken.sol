// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IDSRegistryService} from "../../../../interfaces/external/securitize/IDSRegistryService.sol";
import {IDSToken} from "../../../../interfaces/external/securitize/IDSToken.sol";

contract MockDSToken is ERC20, IDSToken, IDSRegistryService {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint8 public constant override NONE = 0;
    uint8 public constant override KYC_APPROVED = 1;
    uint8 public constant override ACCREDITED = 2;
    uint8 public constant override QUALIFIED = 4;
    uint8 public constant override PROFESSIONAL = 8;

    uint8 public constant override PENDING = 0;
    uint8 public constant override APPROVED = 1;
    uint8 public constant override REJECTED = 2;

    uint256 public constant override REGISTRY_SERVICE = 4;
    uint256 public constant override TRUST_SERVICE = 8;

    address public admin;
    mapping(address registrar => bool) public isRegistrar;

    mapping(string investorId => bool) public override isInvestor;
    mapping(string investorId => EnumerableSet.AddressSet) internal _wallets;
    mapping(address wallet => string investorId) internal _investorId;

    error CallerIsNotAdmin(address caller);
    error CallerIsNotAdminOrRegistrar(address caller);
    error CannotTransfer(address from, address to);
    error InvalidServiceId(uint256 serviceId);
    error InvestorNotFound(address wallet);
    error InvestorNotRegistered(string investorId);

    modifier onlyAdmin() {
        if (msg.sender != admin) revert CallerIsNotAdmin(msg.sender);
        _;
    }

    modifier onlyAdminOrRegistrar() {
        if (msg.sender != admin && !isRegistrar[msg.sender]) revert CallerIsNotAdminOrRegistrar(msg.sender);
        _;
    }

    constructor(address admin_) ERC20("Mock DSToken", "MDSToken") {
        admin = admin_;
    }

    function getDSService(uint256 serviceId) external view override returns (address) {
        if (serviceId != REGISTRY_SERVICE && serviceId != TRUST_SERVICE) revert InvalidServiceId(serviceId);
        return address(this);
    }

    function registerInvestor(string calldata investorId, string calldata) external override onlyAdmin {
        isInvestor[investorId] = true;
    }

    function addWallet(address wallet, string calldata investorId) external override onlyAdminOrRegistrar {
        if (!isInvestor[investorId]) revert InvestorNotRegistered(investorId);
        _wallets[investorId].add(wallet);
        _investorId[wallet] = investorId;
    }

    function getInvestor(address wallet) external view override returns (string memory) {
        return _investorId[wallet];
    }

    function isWallet(address wallet) public view override returns (bool) {
        return bytes(_investorId[wallet]).length > 0;
    }

    function setRegistrar(address retistrar, bool status) external onlyAdmin {
        isRegistrar[retistrar] = status;
    }

    function issueTokens(address to, uint256 amount) external override onlyAdmin {
        if (!isWallet(to)) revert InvestorNotFound(to);
        _mint(to, amount);
    }

    function setCountry(string calldata investorId, string calldata country) external view override onlyAdmin {}

    function setAttribute(
        string calldata investorId,
        uint8 attributeId,
        uint256 value,
        uint256 expiry,
        string calldata proof
    ) external view override onlyAdmin {}

    function burn(address from, uint256 amount, string calldata) external override onlyAdmin {
        if (!isWallet(from)) revert InvestorNotFound(from);
        _burn(from, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal view override {
        if (from != address(0) && !isWallet(from) || to != address(0) && !isWallet(to)) {
            revert CannotTransfer(from, to);
        }
    }
}
