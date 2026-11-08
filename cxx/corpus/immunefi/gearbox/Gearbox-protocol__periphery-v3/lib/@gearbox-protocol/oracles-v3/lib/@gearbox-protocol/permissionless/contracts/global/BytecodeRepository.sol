// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {LibString} from "@solady/utils/LibString.sol";
import {SSTORE2} from "@solady/utils/SSTORE2.sol";

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {SanityCheckTrait} from "@gearbox-protocol/core-v3/contracts/traits/SanityCheckTrait.sol";

import {EIP712Mainnet} from "../helpers/EIP712Mainnet.sol";
import {IBytecodeRepository} from "../interfaces/IBytecodeRepository.sol";
import {AuditReport, Bytecode, BytecodePointer} from "../interfaces/Types.sol";
import {AP_BYTECODE_REPOSITORY} from "../libraries/ContractLiterals.sol";
import {Domain} from "../libraries/Domain.sol";
import {ImmutableOwnableTrait} from "../traits/ImmutableOwnableTrait.sol";

/// @title Bytecode repository
contract BytecodeRepository is ImmutableOwnableTrait, SanityCheckTrait, IBytecodeRepository, EIP712Mainnet {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.UintSet;
    using LibString for bytes32;
    using LibString for string;
    using LibString for uint256;
    using Domain for bytes32;

    /// @dev Internal struct with version info for a given contract type
    struct VersionInfo {
        address owner;
        uint256 latest;
        mapping(uint256 majorVersion => uint256) latestByMajor;
        mapping(uint256 minorVersion => uint256) latestByMinor;
        EnumerableSet.UintSet versionsSet;
    }

    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Contract type
    bytes32 public constant override contractType = AP_BYTECODE_REPOSITORY;

    /// @notice Bytecode typehash
    bytes32 public constant override BYTECODE_TYPEHASH =
        keccak256("Bytecode(bytes32 contractType,uint256 version,bytes initCode,address author,string source)");

    /// @notice Audit report typehash
    bytes32 public constant override AUDIT_REPORT_TYPEHASH =
        keccak256("AuditReport(bytes32 bytecodeHash,address auditor,string reportUrl)");

    /// @dev Mapping from `deployedContract` deployed from the repository to its bytecode hash
    mapping(address deployedContract => bytes32) _deployedContractBytecodeHashes;

    /// @dev Mapping from `bytecodeHash` to pointer to bytecode with given hash
    mapping(bytes32 bytecodeHash => BytecodePointer) internal _bytecodeByHash;

    /// @dev Mapping from `bytecodeHash` to its audit reports
    mapping(bytes32 bytecodeHash => AuditReport[]) internal _auditReports;

    /// @dev Mapping from `cType` to `ver` to allowed bytecode hash
    mapping(bytes32 cType => mapping(uint256 ver => bytes32 bytecodeHash)) internal _allowedBytecodeHashes;

    /// @dev Set of system domains
    EnumerableSet.Bytes32Set internal _systemDomainsSet;

    /// @dev Set of public domains
    EnumerableSet.Bytes32Set internal _publicDomainsSet;

    /// @dev Set of approved auditors
    EnumerableSet.AddressSet internal _auditorsSet;

    /// @dev Mapping from `auditor` to their name
    mapping(address auditor => string) internal _auditorNames;

    /// @dev Mapping from `initCodeHash` to whether it is forbidden
    mapping(bytes32 initCodeHash => bool) internal _isInitCodeForbidden;

    /// @dev Mapping from `token` to its specific postfix
    mapping(address token => bytes32) internal _tokenSpecificPostfixes;

    /// @dev Mapping from `cType` to its version info
    mapping(bytes32 cType => VersionInfo) internal _versionInfo;

    /// @notice Constructor
    /// @param owner_ Owner of the bytecode repository
    constructor(address owner_)
        EIP712Mainnet(contractType.fromSmallString(), version.toString())
        ImmutableOwnableTrait(owner_)
    {}

    // --------------- //
    // EIP-712 GETTERS //
    // --------------- //

    /// @notice Returns the domain separator
    function domainSeparatorV4() external view override returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice Computes bytecode's struct hash
    /// @dev `authorSignature` field is ignored
    function computeBytecodeHash(Bytecode calldata bytecode) public pure override returns (bytes32) {
        return keccak256(
            abi.encode(
                BYTECODE_TYPEHASH,
                bytecode.contractType,
                bytecode.version,
                keccak256(bytecode.initCode),
                bytecode.author,
                keccak256(bytes(bytecode.source))
            )
        );
    }

    /// @notice Computes audit report's struct hash
    /// @dev `signature` field is ignored
    function computeAuditReportHash(bytes32 bytecodeHash, AuditReport calldata report)
        public
        pure
        override
        returns (bytes32)
    {
        return keccak256(
            abi.encode(AUDIT_REPORT_TYPEHASH, bytecodeHash, report.auditor, keccak256(bytes(report.reportUrl)))
        );
    }

    // ------------------- //
    // DEPLOYING CONTRACTS //
    // ------------------- //

    /// @notice Whether `deployedContract` was deployed from the repository
    function isDeployedFromRepository(address deployedContract) external view override returns (bool) {
        return _deployedContractBytecodeHashes[deployedContract] != bytes32(0);
    }

    /// @notice Returns bytecode hash for `deployedContract` deployed from the repository
    function getDeployedContractBytecodeHash(address deployedContract) external view override returns (bytes32) {
        return _deployedContractBytecodeHashes[deployedContract];
    }

    /// @notice Computes the address at which a contract of a given type and version
    ///         with given constructor parameters and salt would be deployed
    /// @dev Deployer's address is mixed with salt to prevent front-running using collisions
    function computeAddress(bytes32 cType, uint256 ver, bytes memory constructorParams, bytes32 salt, address deployer)
        external
        view
        override
        returns (address)
    {
        bytes32 bytecodeHash = _allowedBytecodeHashes[cType][ver];
        BytecodePointer storage bytecode = _bytecodeByHash[bytecodeHash];
        bytes memory initCode = _readInitCode(bytecode.initCodePointers);

        bytes32 uniqueSalt = keccak256(abi.encode(salt, deployer));
        bytes memory bytecodeWithParams = abi.encodePacked(initCode, constructorParams);
        return Create2.computeAddress(uniqueSalt, keccak256(bytecodeWithParams));
    }

    /// @notice Deploys a contract of a given type and version with given constructor parameters and salt.
    ///         Tries to transfer ownership over the deployed contract to the caller.
    ///         Bytecode must be allowed either as system or public contract, which, in turn, requires it
    ///         to be uploaded and have at least one signed report from approved auditor.
    /// @dev Deployer's address is mixed with salt to prevent front-running using collisions
    /// @dev Reverts if contract's init code is forbidden
    /// @dev Reverts if contract was previously deployed at the same address
    /// @dev Reverts if deployed contract's type or version does not match passed parameters
    function deploy(bytes32 cType, uint256 ver, bytes memory constructorParams, bytes32 salt)
        external
        override
        returns (address newContract)
    {
        bytes32 bytecodeHash = _allowedBytecodeHashes[cType][ver];
        if (bytecodeHash == 0) revert BytecodeIsNotAllowedException(cType, ver);

        BytecodePointer storage bytecode = _bytecodeByHash[bytecodeHash];
        bytes memory initCode = _readInitCode(bytecode.initCodePointers);
        _revertIfInitCodeIsForbidden(initCode);

        bytes32 uniqueSalt = keccak256(abi.encode(salt, msg.sender));
        bytes memory bytecodeWithParams = abi.encodePacked(initCode, constructorParams);
        newContract = Create2.computeAddress(uniqueSalt, keccak256(bytecodeWithParams));

        if (newContract.code.length != 0) revert ContractIsAlreadyDeployedException(newContract);
        Create2.deploy(0, uniqueSalt, bytecodeWithParams);
        if (IVersion(newContract).contractType() != cType || IVersion(newContract).version() != ver) {
            revert InvalidBytecodeException(bytecodeHash);
        }

        _deployedContractBytecodeHashes[newContract] = bytecodeHash;
        emit DeployContract(bytecodeHash, cType, ver, newContract, constructorParams);

        try Ownable(newContract).transferOwnership(msg.sender) {} catch {}
    }

    // ------------------ //
    // UPLOADING BYTECODE //
    // ------------------ //

    /// @notice Returns bytecode with `bytecodeHash`
    /// @dev Reverts if bytecode is not uploaded
    function getBytecode(bytes32 bytecodeHash) external view override returns (Bytecode memory) {
        BytecodePointer memory bytecode = _bytecodeByHash[bytecodeHash];
        if (bytecode.initCodePointers.length == 0) revert BytecodeIsNotUploadedException(bytecodeHash);
        return Bytecode({
            contractType: bytecode.contractType,
            version: bytecode.version,
            initCode: _readInitCode(bytecode.initCodePointers),
            author: bytecode.author,
            source: bytecode.source,
            authorSignature: bytecode.authorSignature
        });
    }

    /// @notice Whether bytecode with `bytecodeHash` is uploaded
    function isBytecodeUploaded(bytes32 bytecodeHash) public view override returns (bool) {
        return _bytecodeByHash[bytecodeHash].initCodePointers.length != 0;
    }

    /// @notice Uploads new contract bytecode to the repository.
    ///         Simply uploading the bytecode is not enough to deploy a contract with it, see `deploy` for details.
    /// @dev Reverts if bytecode's contract type is invalid or version is less than `100` or greater than `999`
    /// @dev Reverts if bytecode for given contract type and version is already allowed
    /// @dev Reverts if author is zero address or if their signature is invalid
    /// @dev Reverts if init code is empty
    /// @dev On mainnet, only author of the bytecode can upload it
    function uploadBytecode(Bytecode calldata bytecode) external override nonZeroAddress(bytecode.author) {
        bytes32 bytecodeHash = computeBytecodeHash(bytecode);
        if (isBytecodeUploaded(bytecodeHash)) return;

        _validateContractType(bytecode.contractType);
        _validateVersion(bytecode.contractType, bytecode.version);
        if (_allowedBytecodeHashes[bytecode.contractType][bytecode.version] != 0) {
            revert BytecodeIsAlreadyAllowedException(bytecode.contractType, bytecode.version);
        }

        if (block.chainid == 1 && msg.sender != bytecode.author) revert CallerIsNotBytecodeAuthorException(msg.sender);
        address author = ECDSA.recover(_hashTypedDataV4(bytecodeHash), bytecode.authorSignature);
        if (author != bytecode.author) revert InvalidAuthorSignatureException(author);

        address[] memory initCodePointers = _writeInitCode(bytecode.initCode);
        _bytecodeByHash[bytecodeHash] = BytecodePointer({
            contractType: bytecode.contractType,
            version: bytecode.version,
            initCodePointers: initCodePointers,
            author: bytecode.author,
            source: bytecode.source,
            authorSignature: bytecode.authorSignature
        });
        emit UploadBytecode(
            bytecodeHash,
            bytecode.contractType,
            bytecode.version,
            bytecode.author,
            bytecode.source,
            bytecode.authorSignature
        );
    }

    /// @dev Stores contract's init code using `SSTORE2`, splitting it into chunks if needed
    function _writeInitCode(bytes calldata initCode) internal returns (address[] memory initCodePointers) {
        uint256 chunkSize = 24500; // small buffer to account for `SSTORE2` overhead
        if (initCode.length == 0) revert InitCodeIsEmptyException();
        uint256 len = (initCode.length - 1) / chunkSize + 1;
        initCodePointers = new address[](len);
        for (uint256 i; i < len; ++i) {
            uint256 start = i * chunkSize;
            uint256 end = start + chunkSize;
            if (end > initCode.length) end = initCode.length;
            initCodePointers[i] = SSTORE2.write(initCode[start:end]);
        }
    }

    /// @dev Reads stored contract's init code using `SSTORE2`
    function _readInitCode(address[] memory initCodePointers) internal view returns (bytes memory initCode) {
        for (uint256 i; i < initCodePointers.length; ++i) {
            initCode = bytes.concat(initCode, SSTORE2.read(initCodePointers[i]));
        }
    }

    // ----------------- //
    // AUDITING BYTECODE //
    // ----------------- //

    /// @notice Whether bytecode with `bytecodeHash` is signed at least by one approved auditor
    function isBytecodeAudited(bytes32 bytecodeHash) public view override returns (bool) {
        uint256 len = _auditReports[bytecodeHash].length;
        for (uint256 i; i < len; ++i) {
            AuditReport memory report = _auditReports[bytecodeHash][i];
            if (isAuditor(report.auditor)) return true;
        }
        return false;
    }

    /// @notice Returns all audit reports for `bytecodeHash`
    function getAuditReports(bytes32 bytecodeHash) external view override returns (AuditReport[] memory) {
        return _auditReports[bytecodeHash];
    }

    /// @notice Returns audit report at `index` for `bytecodeHash`
    function getAuditReport(bytes32 bytecodeHash, uint256 index) external view override returns (AuditReport memory) {
        return _auditReports[bytecodeHash][index];
    }

    /// @notice Returns number of audit reports for `bytecodeHash`
    function getNumAuditReports(bytes32 bytecodeHash) external view override returns (uint256) {
        return _auditReports[bytecodeHash].length;
    }

    /// @notice Submits signed audit report for bytecode with `bytecodeHash`
    /// @dev Reverts if bytecode is not uploaded
    /// @dev Reverts if auditor is not approved, already signed bytecode, or their signature is invalid
    function submitAuditReport(bytes32 bytecodeHash, AuditReport calldata auditReport) external override {
        if (!isBytecodeUploaded(bytecodeHash)) revert BytecodeIsNotUploadedException(bytecodeHash);
        if (!_auditorsSet.contains(auditReport.auditor)) revert AuditorIsNotApprovedException(auditReport.auditor);

        bytes32 reportHash = computeAuditReportHash(bytecodeHash, auditReport);
        address auditor = ECDSA.recover(_hashTypedDataV4(reportHash), auditReport.signature);
        if (auditor != auditReport.auditor) revert InvalidAuditorSignatureException(auditor);

        AuditReport[] storage reports = _auditReports[bytecodeHash];
        uint256 len = reports.length;
        for (uint256 i; i < len; ++i) {
            if (keccak256(reports[i].signature) == keccak256(auditReport.signature)) {
                revert BytecodeIsAlreadySignedByAuditorException(bytecodeHash, auditor);
            }
        }
        reports.push(auditReport);
        emit AuditBytecode(bytecodeHash, auditor, auditReport.reportUrl, auditReport.signature);
    }

    // ----------------- //
    // ALLOWING BYTECODE //
    // ----------------- //

    /// @notice Returns the allowed bytecode hash for `cType` and `ver`
    function getAllowedBytecodeHash(bytes32 cType, uint256 ver) external view override returns (bytes32) {
        return _allowedBytecodeHashes[cType][ver];
    }

    /// @notice Returns the owner of `cType`
    function getContractTypeOwner(bytes32 cType) external view override returns (address) {
        return _versionInfo[cType].owner;
    }

    /// @notice Marks bytecode with `bytecodeHash` as allowed system contract.
    ///         Adds bytecode's domain to the list of system domains.
    /// @dev Can only be called by the owner
    /// @dev Reverts if bytecode is not uploaded or not audited
    /// @dev Reverts if bytecode's contract type is in the list of public domains
    /// @dev Reverts if bytecode with this contract type and version is already allowed
    function allowSystemContract(bytes32 bytecodeHash) external override onlyOwner {
        if (!isBytecodeUploaded(bytecodeHash)) revert BytecodeIsNotUploadedException(bytecodeHash);
        if (!isBytecodeAudited(bytecodeHash)) revert BytecodeIsNotAuditedException(bytecodeHash);

        BytecodePointer storage bytecode = _bytecodeByHash[bytecodeHash];
        bytes32 cType = bytecode.contractType;
        _addSystemDomain(cType.extractDomain());

        _allowContract(bytecodeHash, cType, bytecode.version);
    }

    /// @notice Marks bytecode with `bytecodeHash` as allowed public contract.
    ///         Sets bytecode's author as contract type owner.
    /// @dev Reverts if bytecode is not uploaded or not audited
    /// @dev Reverts if bytecode's contract type is not in the list of public domains
    /// @dev Reverts if bytecode's author is not contract type owner
    /// @dev Reverts if bytecode with this contract type and version is already allowed
    function allowPublicContract(bytes32 bytecodeHash) external override {
        if (!isBytecodeUploaded(bytecodeHash)) revert BytecodeIsNotUploadedException(bytecodeHash);
        if (!isBytecodeAudited(bytecodeHash)) revert BytecodeIsNotAuditedException(bytecodeHash);

        BytecodePointer storage bytecode = _bytecodeByHash[bytecodeHash];
        bytes32 cType = bytecode.contractType;
        if (!isPublicDomain(cType.extractDomain())) revert ContractTypeIsNotInPublicDomainException(cType);

        address author = bytecode.author;
        address contractTypeOwner = _versionInfo[cType].owner;
        if (contractTypeOwner == address(0)) {
            _versionInfo[cType].owner = author;
            emit SetContractTypeOwner(cType, author);
        } else if (contractTypeOwner != author) {
            revert AuthorIsNotContractTypeOwnerException(cType, author);
        }

        _allowContract(bytecodeHash, cType, bytecode.version);
    }

    /// @notice Forbids all previously allowed public contracts of a given type, removes type owner and version info.
    ///         Exists primarily to cleanup the repository after public domain squatting by a compromised auditor.
    /// @dev Can only be called by the owner
    function removePublicContractType(bytes32 cType) external override onlyOwner {
        if (!isPublicDomain(cType.extractDomain())) return;

        VersionInfo storage info = _versionInfo[cType];
        if (info.owner != address(0)) {
            info.owner = address(0);
            emit RemoveContractTypeOwner(cType);
        }
        info.latest = 0;
        uint256[] memory versions = info.versionsSet.values();
        uint256 numVersions = versions.length;
        for (uint256 i; i < numVersions; ++i) {
            uint256 ver = versions[i];
            info.versionsSet.remove(ver);
            info.latestByMajor[_getMajorVersion(ver)] = 0;
            info.latestByMinor[_getMinorVersion(ver)] = 0;

            bytes32 bytecodeHash = _allowedBytecodeHashes[cType][ver];
            _allowedBytecodeHashes[cType][ver] = bytes32(0);
            emit ForbidContract(bytecodeHash, cType, ver);
        }
    }

    /// @dev Allows bytecode with `bytecodeHash` for `cType` and `ver`, updates version info for `cType`
    /// @dev Reverts if bytecode is already allowed
    function _allowContract(bytes32 bytecodeHash, bytes32 cType, uint256 ver) internal {
        if (_allowedBytecodeHashes[cType][ver] == bytecodeHash) return;
        if (_allowedBytecodeHashes[cType][ver] != 0) revert BytecodeIsAlreadyAllowedException(cType, ver);
        _allowedBytecodeHashes[cType][ver] = bytecodeHash;
        emit AllowContract(bytecodeHash, cType, ver);

        _updateVersionInfo(cType, ver);
    }

    // ------------------ //
    // DOMAINS MANAGEMENT //
    // ------------------ //

    /// @notice Whether `domain` is in the list of system domains
    function isSystemDomain(bytes32 domain) public view override returns (bool) {
        return _systemDomainsSet.contains(domain);
    }

    /// @notice Returns list of all system domains
    function getSystemDomains() external view override returns (bytes32[] memory) {
        return _systemDomainsSet.values();
    }

    /// @notice Whether `domain` is in the list of public domains
    function isPublicDomain(bytes32 domain) public view override returns (bool) {
        return _publicDomainsSet.contains(domain);
    }

    /// @notice Returns list of all public domains
    function getPublicDomains() external view override returns (bytes32[] memory) {
        return _publicDomainsSet.values();
    }

    /// @notice Adds `domain` to the list of public domains
    /// @dev Can only be called by the owner
    /// @dev Reverts if `domain` is invalid or is already in the list of system domains
    function addPublicDomain(bytes32 domain) external override onlyOwner {
        _validateDomain(domain);
        _addPublicDomain(domain);
    }

    /// @dev Adds `domain` to the list of public domains
    /// @dev Reverts if `domain` is already in the list of system domains
    function _addPublicDomain(bytes32 domain) internal {
        if (isSystemDomain(domain)) revert DomainIsAlreadyMarkedAsSystemException(domain);
        if (_publicDomainsSet.add(domain)) emit AddPublicDomain(domain);
    }

    /// @dev Adds `domain` to the list of system domains
    /// @dev Reverts if `domain` is already in the list of public domains
    function _addSystemDomain(bytes32 domain) internal {
        if (isPublicDomain(domain)) revert DomainIsAlreadyMarkedAsPublicException(domain);
        if (_systemDomainsSet.add(domain)) emit AddSystemDomain(domain);
    }

    // ------------------- //
    // AUDITORS MANAGEMENT //
    // ------------------- //

    /// @notice Whether `auditor` is an approved auditor
    function isAuditor(address auditor) public view override returns (bool) {
        return _auditorsSet.contains(auditor);
    }

    /// @notice Returns list of all approved auditors
    function getAuditors() external view override returns (address[] memory) {
        return _auditorsSet.values();
    }

    /// @notice Returns `auditor`'s name
    function getAuditorName(address auditor) external view override returns (string memory) {
        return _auditorNames[auditor];
    }

    /// @notice Adds `auditor` to the list of approved auditors
    /// @dev Can only be called by the owner
    /// @dev Reverts if `auditor` is zero address
    function addAuditor(address auditor, string memory name) external override onlyOwner nonZeroAddress(auditor) {
        if (!_auditorsSet.add(auditor)) return;
        _auditorNames[auditor] = name;
        emit AddAuditor(auditor, name);
    }

    /// @notice Removes `auditor` from the list of approved auditors
    /// @dev Can only be called by the owner
    function removeAuditor(address auditor) external override onlyOwner {
        if (!_auditorsSet.remove(auditor)) return;
        delete _auditorNames[auditor];
        emit RemoveAuditor(auditor);
    }

    // -------------------- //
    // FORBIDDING INIT CODE //
    // -------------------- //

    /// @notice Whether init code with `initCodeHash` is forbidden
    function isInitCodeForbidden(bytes32 initCodeHash) external view override returns (bool) {
        return _isInitCodeForbidden[initCodeHash];
    }

    /// @notice Permanently marks init code with `initCodeHash` as forbidden
    /// @dev Can only be called by the owner
    function forbidInitCode(bytes32 initCodeHash) external override onlyOwner {
        if (_isInitCodeForbidden[initCodeHash]) return;
        _isInitCodeForbidden[initCodeHash] = true;
        emit ForbidInitCode(initCodeHash);
    }

    /// @dev Reverts if `initCode` is forbidden
    function _revertIfInitCodeIsForbidden(bytes memory initCode) internal view {
        bytes32 initCodeHash = keccak256(initCode);
        if (_isInitCodeForbidden[initCodeHash]) revert InitCodeIsForbiddenException(initCodeHash);
    }

    // ------------------------ //
    // TOKENS WITH CUSTOM LOGIC //
    // ------------------------ //

    /// @notice Returns `token`'s specific postfix, if any
    function getTokenSpecificPostfix(address token) external view override returns (bytes32) {
        return _tokenSpecificPostfixes[token];
    }

    /// @notice Sets `token`'s specific `postfix`
    /// @dev Can only be called by the owner
    /// @dev Reverts if `postfix` is invalid
    function setTokenSpecificPostfix(address token, bytes32 postfix) external override onlyOwner {
        _validatePostfix(postfix);
        if (_tokenSpecificPostfixes[token] == postfix) return;
        _tokenSpecificPostfixes[token] = postfix;
        emit SetTokenSpecificPostfix(token, postfix);
    }

    // --------------- //
    // VERSION CONTROL //
    // --------------- //

    /// @notice Returns all versions for `cType`
    function getVersions(bytes32 cType) external view override returns (uint256[] memory) {
        return _versionInfo[cType].versionsSet.values();
    }

    /// @notice Returns the latest known bytecode version for given `cType`
    /// @dev Reverts if `cType` has no bytecode entries
    function getLatestVersion(bytes32 cType) external view override returns (uint256 ver) {
        ver = _versionInfo[cType].latest;
        if (ver == 0) revert VersionNotFoundException(cType);
    }

    /// @notice Returns the latest known version for given `cType` with matching `majorVersion`
    /// @dev Reverts if `majorVersion` is less than `100` or greater than `999`
    /// @dev Reverts if `cType` has no bytecode entries with matching `majorVersion`
    function getLatestMinorVersion(bytes32 cType, uint256 majorVersion) external view override returns (uint256 ver) {
        _validateVersion(cType, majorVersion);
        ver = _versionInfo[cType].latestByMajor[_getMajorVersion(majorVersion)];
        if (ver == 0) revert VersionNotFoundException(cType);
    }

    /// @notice Returns the latest known version for given `cType` with matching `minorVersion`
    /// @dev Reverts if `minorVersion` is less than `100` or greater than `999`
    /// @dev Reverts if `cType` has no bytecode entries with matching `minorVersion`
    function getLatestPatchVersion(bytes32 cType, uint256 minorVersion) external view override returns (uint256 ver) {
        _validateVersion(cType, minorVersion);
        ver = _versionInfo[cType].latestByMinor[_getMinorVersion(minorVersion)];
        if (ver == 0) revert VersionNotFoundException(cType);
    }

    /// @dev Updates version info for `cType` based on `ver`
    function _updateVersionInfo(bytes32 cType, uint256 ver) internal {
        VersionInfo storage info = _versionInfo[cType];
        if (ver > info.latest) info.latest = ver;
        uint256 majorVersion = _getMajorVersion(ver);
        if (ver > info.latestByMajor[majorVersion]) info.latestByMajor[majorVersion] = ver;
        uint256 minorVersion = _getMinorVersion(ver);
        if (ver > info.latestByMinor[minorVersion]) info.latestByMinor[minorVersion] = ver;
        info.versionsSet.add(ver);
    }

    /// @dev Returns the major version of a given version
    function _getMajorVersion(uint256 ver) internal pure returns (uint256) {
        return ver - ver % 100;
    }

    /// @dev Returns the minor version of a given version
    function _getMinorVersion(uint256 ver) internal pure returns (uint256) {
        return ver - ver % 10;
    }

    /// @dev Reverts if `cType` is invalid
    function _validateContractType(bytes32 cType) internal pure {
        if (!cType.isValidContractType()) revert InvalidContractTypeException(cType);
    }

    /// @dev Reverts if `domain` is invalid
    function _validateDomain(bytes32 domain) internal pure {
        if (!domain.isValidDomain()) revert InvalidDomainException(domain);
    }

    /// @dev Reverts if `postfix` is invalid
    function _validatePostfix(bytes32 postfix) internal pure {
        if (!postfix.isValidPostfix()) revert InvalidPostfixException(postfix);
    }

    /// @dev Reverts if `ver` is less than `100` or greater than `999`
    function _validateVersion(bytes32 cType, uint256 ver) internal pure {
        if (ver < 100 || ver > 999) revert InvalidVersionException(cType, ver);
    }
}
