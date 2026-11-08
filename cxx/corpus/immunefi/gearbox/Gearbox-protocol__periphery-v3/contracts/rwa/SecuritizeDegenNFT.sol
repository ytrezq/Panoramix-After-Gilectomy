// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IAddressProvider} from "@gearbox-protocol/permissionless/contracts/interfaces/IAddressProvider.sol";

import {ISecuritizeDegenNFT} from "../interfaces/ISecuritizeDegenNFT.sol";
import {ISecuritizeRWAFactory} from "../interfaces/ISecuritizeRWAFactory.sol";
import {IVaultRegistrar} from "../interfaces/external/securitize/IVaultRegistrar.sol";
import {
    AddressValidation,
    TYPE_INSTANCE_MANAGER_PROXY,
    TYPE_SECURITIZE_DEGEN_NFT
} from "../libraries/AddressValidation.sol";

/// @title  Securitize Degen NFT
/// @author Gearbox Foundation
/// @notice A Degen NFT that handles the registration of credit accounts and helper accounts in Securitize registries
///         through `VaultRegistrar` contracts, and prevents users from opening non-compliant credit accounts.
contract SecuritizeDegenNFT is ISecuritizeDegenNFT {
    using AddressValidation for IAddressProvider;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct TokenInfo {
        address registrar;
        EnumerableSet.AddressSet operators;
        mapping(address investor => Signature) cachedSignatures;
    }

    bytes32 public constant override contractType = TYPE_SECURITIZE_DEGEN_NFT;
    uint256 public constant override version = 3_10;

    IAddressProvider internal immutable _ADDRESS_PROVIDER;
    ISecuritizeRWAFactory internal immutable _FACTORY;

    EnumerableSet.AddressSet internal _walletsSet;
    EnumerableSet.AddressSet internal _tokensSet;
    mapping(address token => TokenInfo) internal _tokenInfo;

    // --------- //
    // MODIFIERS //
    // --------- //

    modifier onlyFactory() {
        _ensureCallerIsFactory();
        _;
    }

    modifier onlyOperator(address token) {
        _ensureCallerIsOperator(token);
        _;
    }

    modifier onlyInstanceOwner() {
        _ensureCallerIsInstanceOwner();
        _;
    }

    // ----------- //
    // CONSTRUCTOR //
    // ----------- //

    constructor(IAddressProvider addressProvider, ISecuritizeRWAFactory factory) {
        _ADDRESS_PROVIDER = addressProvider;
        _FACTORY = factory;
    }

    // ------- //
    // GETTERS //
    // ------- //

    function serialize() external view override returns (bytes memory) {
        return abi.encode(_FACTORY, getDSTokensData());
    }

    function getFactory() external view override returns (address) {
        return address(_FACTORY);
    }

    function getDSTokensData() public view override returns (DSTokenData[] memory tokens) {
        uint256 length = _tokensSet.length();
        tokens = new DSTokenData[](length);
        for (uint256 i; i < length; ++i) {
            address token = _tokensSet.at(i);
            TokenInfo storage info = _tokenInfo[token];
            tokens[i] = DSTokenData({token: token, registrar: info.registrar, operators: info.operators.values()});
        }
    }

    function getDSTokens() external view override returns (address[] memory) {
        return _tokensSet.values();
    }

    function isDSToken(address token) external view override returns (bool) {
        return _tokensSet.contains(token);
    }

    function getRegistrar(address token) public view override returns (address registrar) {
        registrar = _tokenInfo[token].registrar;
        if (registrar == address(0)) revert RegistrarNotSetForTokenException(token);
    }

    function getOperators(address token) external view override returns (address[] memory) {
        if (!_tokensSet.contains(token)) revert RegistrarNotSetForTokenException(token);
        return _tokenInfo[token].operators.values();
    }

    function isOperator(address token, address operator) public view override returns (bool) {
        if (!_tokensSet.contains(token)) revert RegistrarNotSetForTokenException(token);
        return _tokenInfo[token].operators.contains(operator);
    }

    function getCachedSignature(address investor, address token) external view override returns (Signature memory) {
        if (!_tokensSet.contains(token)) revert RegistrarNotSetForTokenException(token);
        return _tokenInfo[token].cachedSignatures[investor];
    }

    // ------- //
    // ACTIONS //
    // ------- //

    function mint(address wallet) external override onlyFactory {
        if (_walletsSet.add(wallet)) emit Mint(wallet);
    }

    function burn(address wallet, uint256) external override {
        if (!_ADDRESS_PROVIDER.isCreditFacade(msg.sender)) revert CallerIsNotCreditFacadeException(msg.sender);
        if (!_walletsSet.contains(wallet)) revert UnknownWalletException(wallet);
        emit Burn(wallet);
    }

    function cacheRegisterSignatures(address investor, RegisterMessage[] calldata signatures)
        external
        override
        onlyFactory
    {
        uint256 length = signatures.length;
        for (uint256 i; i < length; ++i) {
            address token = signatures[i].token;
            if (!_tokensSet.contains(token)) revert UnknownTokenException(token);
            _tokenInfo[token].cachedSignatures[investor] = signatures[i].signature;
        }
    }

    function registerCreditAccount(address creditAccount, address[] calldata tokens) external override onlyFactory {
        address investor = _getInvestor(creditAccount);
        address wallet = _FACTORY.getWallet(creditAccount);
        uint256 length = tokens.length;
        for (uint256 i; i < length; ++i) {
            address token = tokens[i];
            address registrar = getRegistrar(token);
            if (_isRegistered(registrar, creditAccount, investor)) continue;
            Signature memory signature = _tokenInfo[token].cachedSignatures[investor];
            _registerVault(registrar, creditAccount, investor, signature);
            _registerVault(registrar, wallet, investor, signature);
        }
    }

    function registerHelperAccount(address creditAccount, address helperAccount, address token)
        external
        override
        onlyOperator(token)
    {
        address investor = _getInvestor(creditAccount);
        address registrar = getRegistrar(token);
        if (!_isRegistered(registrar, creditAccount, investor)) {
            revert CreditAccountNotRegisteredException(creditAccount, token);
        }
        Signature memory signature = _tokenInfo[token].cachedSignatures[investor];
        _registerVault(registrar, helperAccount, investor, signature);
    }

    /// @dev This contract is expected to have the operator role in `registrar`
    function addRegistrar(address registrar) external override onlyInstanceOwner {
        address token = IVaultRegistrar(registrar).token();
        if (!_ADDRESS_PROVIDER.isKnownToken(token)) revert UnknownTokenException(token);
        TokenInfo storage info = _tokenInfo[token];
        if (info.registrar == registrar) return;
        _tokensSet.add(token);
        info.registrar = registrar;
        emit SetRegistrar(token, registrar);
    }

    function setOperatorStatus(address token, address operator, bool approved) external override onlyInstanceOwner {
        if (!_tokensSet.contains(token)) revert RegistrarNotSetForTokenException(token);
        TokenInfo storage info = _tokenInfo[token];
        if (approved && info.operators.add(operator) || !approved && info.operators.remove(operator)) {
            emit SetOperatorStatus(token, operator, approved);
        }
    }

    // --------- //
    // INTERNALS //
    // --------- //

    function _ensureCallerIsFactory() internal view {
        if (msg.sender != address(_FACTORY)) revert CallerIsNotFactoryException(msg.sender);
    }

    function _ensureCallerIsOperator(address token) internal view {
        if (!isOperator(token, msg.sender)) revert CallerIsNotOperatorException(token, msg.sender);
    }

    function _ensureCallerIsInstanceOwner() internal view {
        if (msg.sender != _ADDRESS_PROVIDER.getGlobalAddress(TYPE_INSTANCE_MANAGER_PROXY)) {
            revert CallerIsNotInstanceOwnerException(msg.sender);
        }
    }

    function _getInvestor(address creditAccount) internal view returns (address) {
        return _FACTORY.getInvestor(creditAccount);
    }

    function _isRegistered(address registrar, address vault, address investor) internal view returns (bool) {
        return IVaultRegistrar(registrar).isRegistered(vault, investor);
    }

    function _registerVault(address registrar, address vault, address investor, Signature memory signature) internal {
        IVaultRegistrar(registrar).registerVault(vault, investor, signature.deadline, signature.signature);
    }
}
