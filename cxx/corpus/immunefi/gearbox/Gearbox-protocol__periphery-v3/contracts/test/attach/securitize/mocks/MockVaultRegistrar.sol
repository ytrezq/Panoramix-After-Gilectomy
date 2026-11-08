// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {IVaultRegistrar} from "../../../../interfaces/external/securitize/IVaultRegistrar.sol";
import {IDSServiceConsumer} from "../../../../interfaces/external/securitize/IDSServiceConsumer.sol";
import {IDSRegistryService} from "../../../../interfaces/external/securitize/IDSRegistryService.sol";

contract MockVaultRegistrar is IVaultRegistrar, EIP712 {
    bytes32 private constant REGISTER_TYPEHASH =
        keccak256("RegisterVault(address investor,address operator,address token,uint256 nonce,uint256 deadline)");

    address public immutable admin;
    address public immutable override token;

    mapping(address operator => bool) public isOperator;
    mapping(address investor => mapping(address operator => uint256 nonce)) private _operatorNonces;

    error CallerIsNotAdmin(address caller);
    error CallerIsNotOperator(address caller);
    error InvalidInvestorSignature();
    error InvestorNotFound(address investor);
    error NotAnOperator(address operator);
    error SignatureExpired();
    error VaultAlreadyRegistered(address vault);
    error VaultBelongsToDifferentInvestor(address vault, string vaultInvestorId);

    modifier onlyAdmin() {
        if (msg.sender != admin) revert CallerIsNotAdmin(msg.sender);
        _;
    }

    modifier onlyOperator() {
        if (!isOperator[msg.sender]) revert CallerIsNotOperator(msg.sender);
        _;
    }

    constructor(address admin_, address token_) EIP712("VaultRegistrar", "1") {
        admin = admin_;
        token = token_;
    }

    function addOperator(address operator) external override onlyAdmin {
        isOperator[operator] = true;
    }

    function registerVault(address vault, address investor, uint256 deadline, bytes calldata signature)
        external
        override
        onlyOperator
    {
        if (block.timestamp > deadline) revert SignatureExpired();

        address operator = msg.sender;
        uint256 nonce = _operatorNonces[investor][operator];

        bytes32 digest =
            _hashTypedDataV4(keccak256(abi.encode(REGISTER_TYPEHASH, investor, operator, token, nonce, deadline)));

        if (!SignatureChecker.isValidSignatureNow(investor, digest, signature)) {
            revert InvalidInvestorSignature();
        }

        _registerVaultInternal(vault, investor);
    }

    function isRegistered(address vault, address investor) external view override returns (bool) {
        uint256 registryServiceId = IDSServiceConsumer(token).REGISTRY_SERVICE();
        IDSRegistryService registryService =
            IDSRegistryService(IDSServiceConsumer(token).getDSService(registryServiceId));

        string memory vaultInvestorId = registryService.getInvestor(vault);
        if (bytes(vaultInvestorId).length == 0) {
            return false;
        }

        string memory investorId = registryService.getInvestor(investor);
        if (bytes(investorId).length == 0) {
            return false;
        }

        if (keccak256(bytes(vaultInvestorId)) != keccak256(bytes(investorId))) {
            return false;
        }

        return true;
    }

    function operatorNonce(address investor, address operator) external view override returns (uint256) {
        return _operatorNonces[investor][operator];
    }

    function invalidateOperatorPermission(address operator) external override {
        ++_operatorNonces[msg.sender][operator];
    }

    function _validateVaultBelongsToInvestor(
        address vault,
        string memory vaultInvestorId,
        string memory expectedInvestorId
    ) private pure {
        if (keccak256(bytes(vaultInvestorId)) != keccak256(bytes(expectedInvestorId))) {
            revert VaultBelongsToDifferentInvestor(vault, vaultInvestorId);
        }
    }

    function _registerVaultInternal(address vault, address investor) internal {
        address _token = token;

        uint256 registryServiceId = IDSServiceConsumer(_token).REGISTRY_SERVICE();
        IDSRegistryService registryService =
            IDSRegistryService(IDSServiceConsumer(_token).getDSService(registryServiceId));

        string memory investorId = registryService.getInvestor(investor);
        if (bytes(investorId).length == 0) {
            revert InvestorNotFound(investor);
        }

        string memory vaultInvestorId = registryService.getInvestor(vault);
        if (bytes(vaultInvestorId).length > 0) {
            _validateVaultBelongsToInvestor(vault, vaultInvestorId, investorId);
            revert VaultAlreadyRegistered(vault);
        }

        registryService.addWallet(vault, investorId);
    }
}
