// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC5267} from "@openzeppelin/contracts/interfaces/IERC5267.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {ISecuritizeDegenNFT} from "../../../interfaces/ISecuritizeDegenNFT.sol";
import {ISecuritizeRWAFactory} from "../../../interfaces/ISecuritizeRWAFactory.sol";
import {IRWAFactorySubcompressor} from "../../../interfaces/base/IRWAFactorySubcompressor.sol";
import {IDSRegistryService} from "../../../interfaces/external/securitize/IDSRegistryService.sol";
import {IDSToken} from "../../../interfaces/external/securitize/IDSToken.sol";
import {IVaultRegistrar} from "../../../interfaces/external/securitize/IVaultRegistrar.sol";

import {DOMAIN_RWA_FACTORY, TYPE_TOKEN_COMPRESSOR} from "../../../libraries/AddressValidation.sol";

contract SecuritizeRWAFactorySubcompressor is IRWAFactorySubcompressor {
    struct Domain {
        string name;
        string version;
        uint256 chainId;
        address verifyingContract;
    }

    struct RegisterVaultMessage {
        Domain domain;
        address investor;
        address operator;
        address token;
        uint256 nonce;
        uint256 deadline;
    }

    bytes32 public constant override contractType = "GLOBAL::SECURITIZE_RWA_F_SC";
    uint256 public constant override version = 3_10;

    function getCompressedType() external pure override returns (bytes32, bytes32) {
        return (DOMAIN_RWA_FACTORY, "SECURITIZE");
    }

    /// @dev Empty as `serialize` returns all factory-level data
    function getFactoryData(address) external pure override returns (bytes memory) {
        return "";
    }

    function getInvestorData(address investor, address factory) external view override returns (bytes memory) {
        address degenNFT = _getDegenNFT(factory);
        ISecuritizeDegenNFT.DSTokenData[] memory tokens = ISecuritizeDegenNFT(degenNFT).getDSTokensData();
        uint256 numTokens = tokens.length;

        // tokens where investor is registered
        address[] memory registeredTokens = new address[](numTokens);
        uint256 numRegistered;
        for (uint256 i; i < numTokens; ++i) {
            address token = tokens[i].token;
            if (_isInvestor(token, investor)) registeredTokens[numRegistered++] = token;
        }
        assembly {
            mstore(registeredTokens, numRegistered)
        }

        // cached investor's signatures that are still valid and can be reused
        ISecuritizeDegenNFT.RegisterMessage[] memory cachedSignatures =
            new ISecuritizeDegenNFT.RegisterMessage[](numTokens);
        uint256 numValid;
        for (uint256 i; i < numTokens; ++i) {
            address token = tokens[i].token;
            ISecuritizeDegenNFT.Signature memory signature =
                ISecuritizeDegenNFT(degenNFT).getCachedSignature(investor, token);

            if (_isValidSignature(signature, tokens[i].registrar, investor, degenNFT, token)) {
                cachedSignatures[numValid++] = ISecuritizeDegenNFT.RegisterMessage(token, signature);
            }
        }
        assembly {
            mstore(cachedSignatures, numValid)
        }

        // EIP-712 messages to sign to allow factory to register credit accounts
        RegisterVaultMessage[] memory registerVaultMessages = new RegisterVaultMessage[](numTokens);
        for (uint256 i; i < numTokens; ++i) {
            registerVaultMessages[i] =
                _getRegisterVaultMessage(tokens[i].registrar, tokens[i].token, investor, degenNFT);
        }

        return abi.encode(registeredTokens, cachedSignatures, registerVaultMessages);
    }

    function getCreditAccountData(address creditAccount, address factory)
        external
        view
        override
        returns (bytes memory)
    {
        address investor = ISecuritizeRWAFactory(factory).getInvestor(creditAccount);
        address degenNFT = _getDegenNFT(factory);
        ISecuritizeDegenNFT.DSTokenData[] memory tokens = ISecuritizeDegenNFT(degenNFT).getDSTokensData();
        uint256 numTokens = tokens.length;

        // tokens where credit account is registered as investor's vault
        address[] memory registeredTokens = new address[](numTokens);
        uint256 numRegistered;
        for (uint256 i; i < numTokens; ++i) {
            if (_isRegistered(tokens[i].registrar, creditAccount, investor)) {
                registeredTokens[numRegistered++] = tokens[i].token;
            }
        }
        assembly {
            mstore(registeredTokens, numRegistered)
        }

        return abi.encode(registeredTokens);
    }

    // --------- //
    // INTERNALS //
    // --------- //

    function _getDegenNFT(address factory) internal view returns (address) {
        return ISecuritizeRWAFactory(factory).getDegenNFT();
    }

    function _isInvestor(address token, address investor) internal view returns (bool) {
        address registryService = IDSToken(token).getDSService(IDSToken(token).REGISTRY_SERVICE());
        string memory investorId = IDSRegistryService(registryService).getInvestor(investor);
        return IDSRegistryService(registryService).isInvestor(investorId);
    }

    function _isRegistered(address registrar, address vault, address investor) internal view returns (bool) {
        return IVaultRegistrar(registrar).isRegistered(vault, investor);
    }

    function _isValidSignature(
        ISecuritizeDegenNFT.Signature memory signature,
        address registrar,
        address investor,
        address operator,
        address token
    ) internal view returns (bool) {
        if (block.timestamp > signature.deadline) return false;

        uint256 nonce = _getNonce(registrar, investor, operator);
        bytes32 digest = ECDSA.toTypedDataHash(
            _buildDomainSeparator(registrar),
            keccak256(
                abi.encode(
                    keccak256(
                        "RegisterVault(address investor,address operator,address token,uint256 nonce,uint256 deadline)"
                    ),
                    investor,
                    operator,
                    token,
                    nonce,
                    signature.deadline
                )
            )
        );

        return SignatureChecker.isValidSignatureNow(investor, digest, signature.signature);
    }

    function _buildDomainSeparator(address registrar) internal view returns (bytes32) {
        Domain memory domain = _getDomain(registrar);
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(domain.name)),
                keccak256(bytes(domain.version)),
                domain.chainId,
                domain.verifyingContract
            )
        );
    }

    function _getRegisterVaultMessage(address registrar, address token, address investor, address operator)
        internal
        view
        returns (RegisterVaultMessage memory)
    {
        return RegisterVaultMessage({
            domain: _getDomain(registrar),
            investor: investor,
            operator: operator,
            token: token,
            nonce: _getNonce(registrar, investor, operator),
            deadline: type(uint256).max
        });
    }

    function _getDomain(address registrar) internal view returns (Domain memory) {
        (, string memory name, string memory version_, uint256 chainId, address verifyingContract,,) =
            IERC5267(registrar).eip712Domain();
        return Domain(name, version_, chainId, verifyingContract);
    }

    function _getNonce(address registrar, address investor, address operator) internal view returns (uint256) {
        return IVaultRegistrar(registrar).operatorNonce(investor, operator);
    }
}
