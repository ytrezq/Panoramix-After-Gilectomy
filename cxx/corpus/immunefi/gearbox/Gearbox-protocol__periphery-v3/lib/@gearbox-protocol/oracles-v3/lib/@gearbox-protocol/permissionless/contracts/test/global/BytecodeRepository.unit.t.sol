// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IBytecodeRepository} from "../../interfaces/IBytecodeRepository.sol";
import {AuditReport, Bytecode} from "../../interfaces/Types.sol";
import {IImmutableOwnableTrait} from "../../interfaces/base/IImmutableOwnableTrait.sol";

import {MockContract} from "../mocks/MockContract.sol";
import {BytecodeRepositoryHarness} from "./BytecodeRepositoryHarness.sol";

contract BytecodeRepositoryUnitTest is Test {
    BytecodeRepositoryHarness public bcr;

    address public owner;
    VmSafe.Wallet public author;
    VmSafe.Wallet public auditor;

    bytes32 public publicBytecodeHash;
    bytes32 public systemBytecodeHash;

    // ----- //
    // SETUP //
    // ----- //

    function setUp() public {
        owner = makeAddr("Owner");
        author = vm.createWallet("Test Author");
        auditor = vm.createWallet("Test Auditor");

        bcr = new BytecodeRepositoryHarness(owner);

        vm.startPrank(owner);
        bcr.addAuditor(auditor.addr, "Test Auditor");
        bcr.addPublicDomain("PUBLIC");
        vm.stopPrank();

        vm.startPrank(author.addr);
        Bytecode memory publicBytecode = _getTestBytecode("PUBLIC::MOCK", 300);
        Bytecode memory systemBytecode = _getTestBytecode("SYSTEM::MOCK", 300);
        bcr.uploadBytecode(publicBytecode);
        bcr.uploadBytecode(systemBytecode);
        vm.stopPrank();

        vm.startPrank(auditor.addr);
        publicBytecodeHash = bcr.computeBytecodeHash(publicBytecode);
        systemBytecodeHash = bcr.computeBytecodeHash(systemBytecode);
        bcr.submitAuditReport(publicBytecodeHash, _getTestAuditReport(publicBytecodeHash));
        bcr.submitAuditReport(systemBytecodeHash, _getTestAuditReport(systemBytecodeHash));
        vm.stopPrank();

        vm.startPrank(owner);
        bcr.allowPublicContract(publicBytecodeHash);
        bcr.allowSystemContract(systemBytecodeHash);
        vm.stopPrank();
    }

    /// @notice U:[BCR-1]: Setup is correct
    function test_U_BCR_01_setup_is_correct() public view {
        assertEq(bcr.owner(), owner);

        assertTrue(bcr.isAuditor(auditor.addr));
        assertTrue(bcr.isPublicDomain("PUBLIC"));
        assertTrue(bcr.isSystemDomain("SYSTEM"));

        assertTrue(bcr.isBytecodeUploaded(publicBytecodeHash));
        assertTrue(bcr.isBytecodeAudited(publicBytecodeHash));
        assertEq(bcr.getAllowedBytecodeHash("PUBLIC::MOCK", 300), publicBytecodeHash);

        assertTrue(bcr.isBytecodeUploaded(systemBytecodeHash));
        assertTrue(bcr.isBytecodeAudited(systemBytecodeHash));
        assertEq(bcr.getAllowedBytecodeHash("SYSTEM::MOCK", 300), systemBytecodeHash);
    }

    // ---------------- //
    // DEPLOYMENT TESTS //
    // ---------------- //

    /// @notice U:[BCR-2]: `deploy` works correctly
    function test_U_BCR_02_deploy_works_correctly() public {
        bytes32 salt = keccak256("test salt");
        bytes memory constructorParams = abi.encode(bytes32("PUBLIC::MOCK"), uint256(300));

        address expectedAddr = bcr.computeAddress("PUBLIC::MOCK", 300, constructorParams, salt, address(this));
        assertFalse(bcr.isDeployedFromRepository(expectedAddr));

        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.DeployContract(
            publicBytecodeHash, bytes32("PUBLIC::MOCK"), 300, expectedAddr, constructorParams
        );

        vm.expectCall(expectedAddr, abi.encodeWithSignature("transferOwnership(address)", address(this)));

        address deployedAddr = bcr.deploy("PUBLIC::MOCK", 300, constructorParams, salt);
        assertEq(deployedAddr, expectedAddr);

        // Verify contract was deployed
        assertTrue(deployedAddr.code.length > 0);

        // Verify deployment was recorded
        assertTrue(bcr.isDeployedFromRepository(deployedAddr));
        assertEq(bcr.getDeployedContractBytecodeHash(deployedAddr), publicBytecodeHash);

        // Reverts if trying to deploy again with same parameters
        vm.expectRevert(
            abi.encodeWithSelector(IBytecodeRepository.ContractIsAlreadyDeployedException.selector, deployedAddr)
        );
        bcr.deploy("PUBLIC::MOCK", 300, constructorParams, salt);
    }

    /// @notice U:[BCR-3]: `deploy` reverts for non-allowed bytecode
    function test_U_BCR_03_deploy_reverts_for_non_allowed_bytecode() public {
        bytes32 salt = keccak256("test salt");
        bytes memory constructorParams = abi.encode(bytes32("PUBLIC::MOCK"), uint256(301));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBytecodeRepository.BytecodeIsNotAllowedException.selector, bytes32("PUBLIC::MOCK"), 301
            )
        );
        bcr.deploy("PUBLIC::MOCK", 301, constructorParams, salt);
    }

    /// @notice U:[BCR-4]: `deploy` reverts for forbidden init code
    function test_U_BCR_04_deploy_reverts_for_forbidden_init_code() public {
        bytes32 salt = keccak256("test salt");
        bytes memory constructorParams = abi.encode(bytes32("PUBLIC::MOCK"), uint256(300));

        // Forbid the init code
        bytes32 initCodeHash = keccak256(type(MockContract).creationCode);
        vm.prank(owner);
        bcr.forbidInitCode(initCodeHash);

        vm.expectRevert(abi.encodeWithSelector(IBytecodeRepository.InitCodeIsForbiddenException.selector, initCodeHash));
        bcr.deploy("PUBLIC::MOCK", 300, constructorParams, salt);
    }

    /// @notice U:[BCR-5]: `deploy` reverts if deployed contract has wrong type or version
    function test_U_BCR_05_deploy_reverts_for_wrong_contract_type_or_version() public {
        bytes32 salt = keccak256("test salt");

        // Wrong version
        bytes memory constructorParams = abi.encode(bytes32("PUBLIC::MOCK"), uint256(301));
        vm.expectRevert(
            abi.encodeWithSelector(IBytecodeRepository.InvalidBytecodeException.selector, publicBytecodeHash)
        );
        bcr.deploy("PUBLIC::MOCK", 300, constructorParams, salt);

        // Wrong type
        constructorParams = abi.encode(bytes32("PUBLIC::MOCK2"), uint256(300));
        vm.expectRevert(
            abi.encodeWithSelector(IBytecodeRepository.InvalidBytecodeException.selector, publicBytecodeHash)
        );
        bcr.deploy("PUBLIC::MOCK", 300, constructorParams, salt);
    }

    // --------------------- //
    // UPLOAD BYTECODE TESTS //
    // --------------------- //

    /// @notice U:[BCR-6]: `uploadBytecode` works correctly
    function test_U_BCR_06_uploadBytecode_works_correctly() public {
        Bytecode memory bytecode = _getTestBytecode("PUBLIC::NEW", 300);
        bytes32 bytecodeHash = bcr.computeBytecodeHash(bytecode);

        assertFalse(bcr.isBytecodeUploaded(bytecodeHash));

        // `getBytecode` reverts for non-uploaded bytecode
        vm.expectRevert(
            abi.encodeWithSelector(IBytecodeRepository.BytecodeIsNotUploadedException.selector, bytecodeHash)
        );
        bcr.getBytecode(bytecodeHash);

        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.UploadBytecode(
            bytecodeHash,
            bytecode.contractType,
            bytecode.version,
            bytecode.author,
            bytecode.source,
            bytecode.authorSignature
        );

        vm.prank(author.addr);
        bcr.uploadBytecode(bytecode);

        assertTrue(bcr.isBytecodeUploaded(bytecodeHash));

        // Verify stored bytecode matches input
        Bytecode memory storedBytecode = bcr.getBytecode(bytecodeHash);
        assertEq(storedBytecode.contractType, bytecode.contractType);
        assertEq(storedBytecode.version, bytecode.version);
        assertEq(storedBytecode.initCode, bytecode.initCode);
        assertEq(storedBytecode.author, bytecode.author);
        assertEq(storedBytecode.source, bytecode.source);
        assertEq(storedBytecode.authorSignature, bytecode.authorSignature);

        // Second upload should not emit event or revert
        vm.prank(author.addr);
        bcr.uploadBytecode(bytecode);

        // Test with empty init code
        bytecode.initCode = new bytes(0);
        bytecode.authorSignature = _signBytecode(author, bytecode);

        vm.expectRevert(abi.encodeWithSelector(IBytecodeRepository.InitCodeIsEmptyException.selector));
        vm.prank(author.addr);
        bcr.uploadBytecode(bytecode);

        // Test with large init code
        bytecode.initCode = new bytes(30000);
        for (uint256 i; i < 30000; ++i) {
            bytecode.initCode[i] = bytes1(uint8((i % 256)));
        }
        bytecode.authorSignature = _signBytecode(author, bytecode);

        vm.prank(author.addr);
        bcr.uploadBytecode(bytecode);

        bytecodeHash = bcr.computeBytecodeHash(bytecode);
        storedBytecode = bcr.getBytecode(bytecodeHash);
        assertEq(storedBytecode.contractType, bytecode.contractType);
        assertEq(storedBytecode.version, bytecode.version);
        assertEq(storedBytecode.initCode, bytecode.initCode);
        assertEq(storedBytecode.author, bytecode.author);
        assertEq(storedBytecode.source, bytecode.source);
        assertEq(storedBytecode.authorSignature, bytecode.authorSignature);
    }

    /// @notice U:[BCR-7]: `uploadBytecode` reverts for invalid contract type or version
    function test_U_BCR_07_uploadBytecode_reverts_for_invalid_contract_type_or_version() public {
        Bytecode memory bytecode;

        vm.startPrank(author.addr);
        bytecode = _getTestBytecode("PUBLIC::", 300);
        vm.expectRevert(
            abi.encodeWithSelector(IBytecodeRepository.InvalidContractTypeException.selector, bytes32("PUBLIC::"))
        );
        bcr.uploadBytecode(bytecode);

        bytecode = _getTestBytecode("PUBLIC::MOCK::NEW", 300);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBytecodeRepository.InvalidContractTypeException.selector, bytes32("PUBLIC::MOCK::NEW")
            )
        );
        bcr.uploadBytecode(bytecode);

        // Test version < 100
        bytecode = _getTestBytecode("PUBLIC::NEW", 99);
        vm.expectRevert(
            abi.encodeWithSelector(IBytecodeRepository.InvalidVersionException.selector, bytes32("PUBLIC::NEW"), 99)
        );
        bcr.uploadBytecode(bytecode);

        // Test version > 999
        bytecode = _getTestBytecode("PUBLIC::NEW", 1000);
        vm.expectRevert(
            abi.encodeWithSelector(IBytecodeRepository.InvalidVersionException.selector, bytes32("PUBLIC::NEW"), 1000)
        );
        bcr.uploadBytecode(bytecode);
        vm.stopPrank();
    }

    /// @notice U:[BCR-8]: `uploadBytecode` reverts if allowed bytecode exists for type and version
    function test_U_BCR_08_uploadBytecode_reverts_if_allowed_bytecode_exists_for_type_and_version() public {
        Bytecode memory bytecode = _getTestBytecode("PUBLIC::MOCK", 300);
        // change link to source and sign again
        bytecode.source = "https://github.com/Gearbox-protocol/even-more-permissionless";
        bytecode.authorSignature = _signBytecode(author, bytecode);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBytecodeRepository.BytecodeIsAlreadyAllowedException.selector, bytes32("PUBLIC::MOCK"), 300
            )
        );
        vm.prank(author.addr);
        bcr.uploadBytecode(bytecode);
    }

    /// @notice U:[BCR-9]: `uploadBytecode` reverts for invalid author or signature
    function test_U_BCR_09_uploadBytecode_reverts_for_invalid_author_or_signature() public {
        Bytecode memory bytecode = _getTestBytecode("PUBLIC::NEW", 300);

        // Test with empty author
        bytecode.author = address(0);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddressException()"));
        vm.prank(author.addr);
        bcr.uploadBytecode(bytecode);

        // Test with invalid author
        bytecode.author = author.addr;
        VmSafe.Wallet memory invalidAuthor = vm.createWallet("Invalid Author");
        bytecode.authorSignature = _signBytecode(invalidAuthor, bytecode);
        vm.expectRevert(
            abi.encodeWithSelector(IBytecodeRepository.InvalidAuthorSignatureException.selector, invalidAuthor.addr)
        );
        vm.prank(author.addr);
        bcr.uploadBytecode(bytecode);

        // Test with invalid signature format
        bytecode.authorSignature = "invalid signature";
        vm.expectRevert(); // Should revert during ECDSA recovery
        vm.prank(author.addr);
        bcr.uploadBytecode(bytecode);
    }

    /// @notice U:[BCR-9]: `uploadBytecode` allows non-author to upload only outside mainnet
    function test_U_BCR_10_uploadBytecode_allows_non_author_to_upload_only_outside_mainnet() public {
        Bytecode memory bytecode = _getTestBytecode("PUBLIC::NEW", 300);
        address notAuthor = makeAddr("Not Author");

        // Set chainId to mainnet
        vm.chainId(1);

        vm.expectRevert(
            abi.encodeWithSelector(IBytecodeRepository.CallerIsNotBytecodeAuthorException.selector, notAuthor)
        );
        vm.prank(notAuthor);
        bcr.uploadBytecode(bytecode);

        // Set chainId to non-mainnet
        vm.chainId(5);

        vm.prank(notAuthor);
        bcr.uploadBytecode(bytecode);
    }

    // -------------------- //
    // AUDIT BYTECODE TESTS //
    // -------------------- //

    /// @notice U:[BCR-11]: `submitAuditReport` works correctly
    function test_U_BCR_11_submitAuditReport_works_correctly() public {
        Bytecode memory bytecode = _getTestBytecode("PUBLIC::NEW", 300);
        vm.prank(author.addr);
        bcr.uploadBytecode(bytecode);

        bytes32 bytecodeHash = bcr.computeBytecodeHash(bytecode);
        assertFalse(bcr.isBytecodeAudited(bytecodeHash));
        assertEq(bcr.getNumAuditReports(bytecodeHash), 0);

        AuditReport memory report = _getTestAuditReport(bytecodeHash);

        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.AuditBytecode(bytecodeHash, auditor.addr, report.reportUrl, report.signature);

        bcr.submitAuditReport(bytecodeHash, report);

        assertTrue(bcr.isBytecodeAudited(bytecodeHash));
        assertEq(bcr.getNumAuditReports(bytecodeHash), 1);
        AuditReport[] memory reports = bcr.getAuditReports(bytecodeHash);
        assertEq(reports.length, 1);
        assertEq(reports[0].auditor, report.auditor);
        assertEq(reports[0].reportUrl, report.reportUrl);
        assertEq(reports[0].signature, report.signature);

        // Reverts if trying to submit same report again
        vm.expectRevert(
            abi.encodeWithSelector(
                IBytecodeRepository.BytecodeIsAlreadySignedByAuditorException.selector, bytecodeHash, auditor.addr
            )
        );
        bcr.submitAuditReport(bytecodeHash, report);

        // Setup second auditor
        VmSafe.Wallet memory auditor2 = vm.createWallet("Test Auditor 2");
        vm.prank(owner);
        bcr.addAuditor(auditor2.addr, "Test Auditor 2");

        // Submit second audit
        AuditReport memory report2 = _getTestAuditReport(bytecodeHash);
        report2.auditor = auditor2.addr;
        report2.signature = _signAuditReport(auditor2, bytecodeHash, report2);
        bcr.submitAuditReport(bytecodeHash, report2);

        // Verify both reports are stored
        assertTrue(bcr.isBytecodeAudited(bytecodeHash));
        assertEq(bcr.getNumAuditReports(bytecodeHash), 2);
        reports = bcr.getAuditReports(bytecodeHash);
        assertEq(reports.length, 2);
        assertEq(reports[0].auditor, report.auditor);
        assertEq(reports[0].reportUrl, report.reportUrl);
        assertEq(reports[0].signature, report.signature);
        assertEq(reports[1].auditor, report2.auditor);
        assertEq(reports[1].reportUrl, report2.reportUrl);
        assertEq(reports[1].signature, report2.signature);
    }

    /// @notice U:[BCR-12]: `submitAuditReport` reverts for non-uploaded bytecode
    function test_U_BCR_12_submitAuditReport_reverts_for_non_uploaded_bytecode() public {
        bytes32 nonExistentHash = keccak256("non existent");
        AuditReport memory report = _getTestAuditReport(nonExistentHash);

        vm.expectRevert(
            abi.encodeWithSelector(IBytecodeRepository.BytecodeIsNotUploadedException.selector, nonExistentHash)
        );
        bcr.submitAuditReport(nonExistentHash, report);
    }

    /// @notice U:[BCR-13]: `submitAuditReport` reverts for invalid auditor or signature
    function test_U_BCR_13_submitAuditReport_reverts_for_invalid_auditor_or_signature() public {
        Bytecode memory bytecode = _getTestBytecode("PUBLIC::NEW", 300);
        vm.prank(author.addr);
        bcr.uploadBytecode(bytecode);

        bytes32 bytecodeHash = bcr.computeBytecodeHash(bytecode);
        AuditReport memory report = _getTestAuditReport(bytecodeHash);

        VmSafe.Wallet memory nonAuditor = vm.createWallet("Non Auditor");

        // Test with wrong signer
        report.signature = _signAuditReport(nonAuditor, bytecodeHash, report);
        vm.expectRevert(
            abi.encodeWithSelector(IBytecodeRepository.InvalidAuditorSignatureException.selector, nonAuditor.addr)
        );
        bcr.submitAuditReport(bytecodeHash, report);

        // Test with non-approved auditor
        report.auditor = nonAuditor.addr;
        report.signature = _signAuditReport(nonAuditor, bytecodeHash, report);
        vm.expectRevert(
            abi.encodeWithSelector(IBytecodeRepository.AuditorIsNotApprovedException.selector, nonAuditor.addr)
        );
        bcr.submitAuditReport(bytecodeHash, report);

        // Test with invalid signature format
        report.signature = "invalid signature";
        vm.expectRevert(); // Should revert during ECDSA recovery
        bcr.submitAuditReport(bytecodeHash, report);
    }

    // -------------------- //
    // ALLOW BYTECODE TESTS //
    // -------------------- //

    /// @notice U:[BCR-14]: `allowSystemContract` works correctly
    function test_U_BCR_14_allowSystemContract_works_correctly() public {
        Bytecode memory bytecode = _getTestBytecode("SYSTEM::MOCK", 301);
        bytes32 bytecodeHash = bcr.computeBytecodeHash(bytecode);

        // Reverts if caller is not owner
        vm.expectRevert(
            abi.encodeWithSelector(IImmutableOwnableTrait.CallerIsNotOwnerException.selector, address(this))
        );
        bcr.allowSystemContract(bytecodeHash);

        // Reverts if bytecode is not uploaded
        vm.expectRevert(
            abi.encodeWithSelector(IBytecodeRepository.BytecodeIsNotUploadedException.selector, bytecodeHash)
        );
        vm.prank(owner);
        bcr.allowSystemContract(bytecodeHash);

        vm.prank(author.addr);
        bcr.uploadBytecode(bytecode);

        // Reverts if bytecode is not audited
        vm.expectRevert(
            abi.encodeWithSelector(IBytecodeRepository.BytecodeIsNotAuditedException.selector, bytecodeHash)
        );
        vm.prank(owner);
        bcr.allowSystemContract(bytecodeHash);

        bcr.submitAuditReport(bytecodeHash, _getTestAuditReport(bytecodeHash));

        assertEq(bcr.getAllowedBytecodeHash("SYSTEM::MOCK", 301), bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.AllowContract(bytecodeHash, "SYSTEM::MOCK", 301);

        vm.prank(owner);
        bcr.allowSystemContract(bytecodeHash);
        assertEq(bcr.getAllowedBytecodeHash("SYSTEM::MOCK", 301), bytecodeHash);

        // Second allowance should be no-op
        vm.prank(owner);
        bcr.allowSystemContract(bytecodeHash);
    }

    /// @notice U:[BCR-15]: `allowSystemContract` correctly handles domain
    function test_U_BCR_15_allowSystemContract_correctly_handles_domain() public {
        // Reverts if domain is already marked as public
        Bytecode memory bytecode = _getTestBytecode("PUBLIC::MOCK2", 300);
        bytes32 bytecodeHash = bcr.computeBytecodeHash(bytecode);

        vm.prank(author.addr);
        bcr.uploadBytecode(bytecode);
        bcr.submitAuditReport(bytecodeHash, _getTestAuditReport(bytecodeHash));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBytecodeRepository.DomainIsAlreadyMarkedAsPublicException.selector, bytes32("PUBLIC")
            )
        );
        vm.prank(owner);
        bcr.allowSystemContract(bytecodeHash);

        // Adds new system domain when allowing contract
        bytecode = _getTestBytecode("SYSTEM2::MOCK", 300);
        bytecodeHash = bcr.computeBytecodeHash(bytecode);

        vm.prank(author.addr);
        bcr.uploadBytecode(bytecode);
        bcr.submitAuditReport(bytecodeHash, _getTestAuditReport(bytecodeHash));

        assertFalse(bcr.isSystemDomain("SYSTEM2"));

        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.AddSystemDomain(bytes32("SYSTEM2"));

        vm.prank(owner);
        bcr.allowSystemContract(bytecodeHash);

        assertTrue(bcr.isSystemDomain("SYSTEM2"));
    }

    /// @notice U:[BCR-16]: `allowPublicContract` works correctly
    function test_U_BCR_16_allowPublicContract_works_correctly() public {
        Bytecode memory bytecode = _getTestBytecode("PUBLIC::MOCK", 301);
        bytes32 bytecodeHash = bcr.computeBytecodeHash(bytecode);

        // Reverts if bytecode is not uploaded
        vm.expectRevert(
            abi.encodeWithSelector(IBytecodeRepository.BytecodeIsNotUploadedException.selector, bytecodeHash)
        );
        bcr.allowPublicContract(bytecodeHash);

        vm.prank(author.addr);
        bcr.uploadBytecode(bytecode);

        // Reverts if bytecode is not audited
        vm.expectRevert(
            abi.encodeWithSelector(IBytecodeRepository.BytecodeIsNotAuditedException.selector, bytecodeHash)
        );
        bcr.allowPublicContract(bytecodeHash);

        bcr.submitAuditReport(bytecodeHash, _getTestAuditReport(bytecodeHash));

        assertEq(bcr.getAllowedBytecodeHash("PUBLIC::MOCK", 301), bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.AllowContract(bytecodeHash, "PUBLIC::MOCK", 301);

        bcr.allowPublicContract(bytecodeHash);

        assertEq(bcr.getAllowedBytecodeHash("PUBLIC::MOCK", 301), bytecodeHash);

        // Second allowance should be no-op
        bcr.allowPublicContract(bytecodeHash);
    }

    /// @notice U:[BCR-17]: `allowPublicContract` correctly handles domain and owner
    function test_U_BCR_17_allowPublicContract_correctly_handles_domain_and_owner() public {
        // Reverts if domain is not market as public
        Bytecode memory bytecode = _getTestBytecode("PUBLIC2::MOCK", 300);
        bytes32 bytecodeHash = bcr.computeBytecodeHash(bytecode);

        vm.prank(author.addr);
        bcr.uploadBytecode(bytecode);
        bcr.submitAuditReport(bytecodeHash, _getTestAuditReport(bytecodeHash));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBytecodeRepository.ContractTypeIsNotInPublicDomainException.selector, bytes32("PUBLIC2::MOCK")
            )
        );
        bcr.allowPublicContract(bytecodeHash);

        // Test owner setting for new contract type
        bytecode = _getTestBytecode("PUBLIC::MOCK2", 300);
        bytecodeHash = bcr.computeBytecodeHash(bytecode);

        vm.prank(author.addr);
        bcr.uploadBytecode(bytecode);
        bcr.submitAuditReport(bytecodeHash, _getTestAuditReport(bytecodeHash));

        assertEq(bcr.getContractTypeOwner("PUBLIC::MOCK2"), address(0));

        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.SetContractTypeOwner(bytes32("PUBLIC::MOCK2"), author.addr);

        bcr.allowPublicContract(bytecodeHash);
        assertEq(bcr.getContractTypeOwner("PUBLIC::MOCK2"), author.addr);

        // Test with different author for existing contract type
        VmSafe.Wallet memory otherAuthor = vm.createWallet("Other Author");
        bytecode = _getTestBytecode("PUBLIC::MOCK2", 301);
        bytecode.author = otherAuthor.addr;
        bytecode.authorSignature = _signBytecode(otherAuthor, bytecode);
        bytecodeHash = bcr.computeBytecodeHash(bytecode);

        vm.prank(otherAuthor.addr);
        bcr.uploadBytecode(bytecode);
        bcr.submitAuditReport(bytecodeHash, _getTestAuditReport(bytecodeHash));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBytecodeRepository.AuthorIsNotContractTypeOwnerException.selector,
                bytes32("PUBLIC::MOCK2"),
                otherAuthor.addr
            )
        );
        bcr.allowPublicContract(bytecodeHash);
    }

    /// @notice U:[BCR-18]: `_allowContract` works correctly
    function test_U_BCR_18_allowContract_works_correctly() public {
        // Test revert if bytecode is already allowed for given type and version
        vm.expectRevert(
            abi.encodeWithSelector(
                IBytecodeRepository.BytecodeIsAlreadyAllowedException.selector, bytes32("PUBLIC::MOCK"), 300
            )
        );
        bcr.exposed_allowContract(keccak256("other hash"), "PUBLIC::MOCK", 300);

        // Test version info updates with multiple versions
        bytes32[] memory hashes = new bytes32[](5);
        for (uint256 i = 0; i < 5; ++i) {
            hashes[i] = keccak256(abi.encode("hash", i));
        }

        // Allow v3.1.0
        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.AllowContract(hashes[0], "PUBLIC::MOCK", 310);
        bcr.exposed_allowContract(hashes[0], "PUBLIC::MOCK", 310);

        // Allow v3.1.1
        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.AllowContract(hashes[1], "PUBLIC::MOCK", 311);
        bcr.exposed_allowContract(hashes[1], "PUBLIC::MOCK", 311);

        // Allow v3.2.0
        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.AllowContract(hashes[2], "PUBLIC::MOCK", 320);
        bcr.exposed_allowContract(hashes[2], "PUBLIC::MOCK", 320);

        // Allow v4.0.0
        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.AllowContract(hashes[3], "PUBLIC::MOCK", 400);
        bcr.exposed_allowContract(hashes[3], "PUBLIC::MOCK", 400);

        // Allow v4.1.0
        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.AllowContract(hashes[4], "PUBLIC::MOCK", 410);
        bcr.exposed_allowContract(hashes[4], "PUBLIC::MOCK", 410);

        // Verify version info
        uint256[] memory versions = bcr.getVersions("PUBLIC::MOCK");
        assertEq(versions.length, 6); // Including v3.0.0 from setup
        assertEq(versions[0], 300);
        assertEq(versions[1], 310);
        assertEq(versions[2], 311);
        assertEq(versions[3], 320);
        assertEq(versions[4], 400);
        assertEq(versions[5], 410);

        // Test latest version queries
        assertEq(bcr.getLatestVersion("PUBLIC::MOCK"), 410);

        // Test latest minor versions
        assertEq(bcr.getLatestMinorVersion("PUBLIC::MOCK", 300), 320); // Latest in v3.x.x
        assertEq(bcr.getLatestMinorVersion("PUBLIC::MOCK", 400), 410); // Latest in v4.x.x

        // Test latest patch versions
        assertEq(bcr.getLatestPatchVersion("PUBLIC::MOCK", 300), 300);
        assertEq(bcr.getLatestPatchVersion("PUBLIC::MOCK", 310), 311);
        assertEq(bcr.getLatestPatchVersion("PUBLIC::MOCK", 320), 320);
        assertEq(bcr.getLatestPatchVersion("PUBLIC::MOCK", 400), 400);
        assertEq(bcr.getLatestPatchVersion("PUBLIC::MOCK", 410), 410);
    }

    /// @notice U:[BCR-19]: `removePublicContractType` works correctly
    function test_U_BCR_19_removePublicContractType_works_correctly() public {
        // Test with non-public domain (should be no-op)
        vm.prank(owner);
        bcr.removePublicContractType("SYSTEM::MOCK");
        assertEq(bcr.getAllowedBytecodeHash("SYSTEM::MOCK", 300), systemBytecodeHash);

        // Add more versions to test cleanup
        bytes32[] memory hashes = new bytes32[](4);
        for (uint256 i = 0; i < 4; ++i) {
            hashes[i] = keccak256(abi.encode("hash", i));
        }

        bcr.exposed_allowContract(hashes[0], "PUBLIC::MOCK", 301);
        bcr.exposed_allowContract(hashes[1], "PUBLIC::MOCK", 310);
        bcr.exposed_allowContract(hashes[2], "PUBLIC::MOCK", 320);
        bcr.exposed_allowContract(hashes[3], "PUBLIC::MOCK", 400);

        // Test with public domain
        assertEq(bcr.getContractTypeOwner("PUBLIC::MOCK"), author.addr);

        // Expect events for all versions
        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.RemoveContractTypeOwner(bytes32("PUBLIC::MOCK"));

        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.ForbidContract(publicBytecodeHash, "PUBLIC::MOCK", 300);
        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.ForbidContract(hashes[0], "PUBLIC::MOCK", 301);
        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.ForbidContract(hashes[1], "PUBLIC::MOCK", 310);
        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.ForbidContract(hashes[2], "PUBLIC::MOCK", 320);
        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.ForbidContract(hashes[3], "PUBLIC::MOCK", 400);

        vm.prank(owner);
        bcr.removePublicContractType("PUBLIC::MOCK");

        // Verify all versions are removed
        assertEq(bcr.getContractTypeOwner("PUBLIC::MOCK"), address(0));
        assertEq(bcr.getAllowedBytecodeHash("PUBLIC::MOCK", 300), bytes32(0));
        assertEq(bcr.getAllowedBytecodeHash("PUBLIC::MOCK", 301), bytes32(0));
        assertEq(bcr.getAllowedBytecodeHash("PUBLIC::MOCK", 310), bytes32(0));
        assertEq(bcr.getAllowedBytecodeHash("PUBLIC::MOCK", 320), bytes32(0));
        assertEq(bcr.getAllowedBytecodeHash("PUBLIC::MOCK", 400), bytes32(0));

        // Verify version info is cleared
        assertEq(bcr.getVersions("PUBLIC::MOCK").length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(IBytecodeRepository.VersionNotFoundException.selector, bytes32("PUBLIC::MOCK"))
        );
        bcr.getLatestVersion("PUBLIC::MOCK");

        uint256[2] memory majors = [uint256(300), 400];
        for (uint256 i; i < 2; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(IBytecodeRepository.VersionNotFoundException.selector, bytes32("PUBLIC::MOCK"))
            );
            bcr.getLatestMinorVersion("PUBLIC::MOCK", majors[i]);
        }

        uint256[4] memory minors = [uint256(300), 310, 320, 400];
        for (uint256 i; i < 4; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(IBytecodeRepository.VersionNotFoundException.selector, bytes32("PUBLIC::MOCK"))
            );
            bcr.getLatestPatchVersion("PUBLIC::MOCK", minors[i]);
        }
    }

    // ------------------------ //
    // AUDITOR MANAGEMENT TESTS //
    // ------------------------ //

    /// @notice U:[BCR-20]: Auditor management works correctly
    function test_U_BCR_20_auditor_management_works_correctly() public {
        address newAuditor = makeAddr("New Auditor");
        string memory auditorName = "New Test Auditor";

        // Only owner can add/remove auditors
        vm.expectRevert(
            abi.encodeWithSelector(IImmutableOwnableTrait.CallerIsNotOwnerException.selector, address(this))
        );
        bcr.addAuditor(newAuditor, auditorName);

        vm.expectRevert(
            abi.encodeWithSelector(IImmutableOwnableTrait.CallerIsNotOwnerException.selector, address(this))
        );
        bcr.removeAuditor(auditor.addr);

        // Can't add zero address as auditor
        vm.expectRevert(abi.encodeWithSignature("ZeroAddressException()"));
        vm.prank(owner);
        bcr.addAuditor(address(0), auditorName);

        // Test adding new auditor
        assertFalse(bcr.isAuditor(newAuditor));

        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.AddAuditor(newAuditor, auditorName);

        vm.prank(owner);
        bcr.addAuditor(newAuditor, auditorName);

        assertTrue(bcr.isAuditor(newAuditor));
        assertEq(bcr.getAuditorName(newAuditor), auditorName);

        // Second add should be no-op
        vm.prank(owner);
        bcr.addAuditor(newAuditor, "Different Name");
        assertEq(bcr.getAuditorName(newAuditor), auditorName);

        // Test removing auditor
        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.RemoveAuditor(auditor.addr);

        vm.prank(owner);
        bcr.removeAuditor(auditor.addr);

        assertFalse(bcr.isAuditor(auditor.addr));
        assertEq(bcr.getAuditorName(auditor.addr), "");
        assertFalse(bcr.isBytecodeAudited(publicBytecodeHash));

        // Second remove should be no-op
        vm.prank(owner);
        bcr.removeAuditor(auditor.addr);
    }

    // ----------------------- //
    // DOMAIN MANAGEMENT TESTS //
    // ----------------------- //

    /// @notice U:[BCR-21]: Domain management works correctly
    function test_U_BCR_21_domain_management_works_correctly() public {
        // Only owner can add domains
        vm.expectRevert(
            abi.encodeWithSelector(IImmutableOwnableTrait.CallerIsNotOwnerException.selector, address(this))
        );
        bcr.addPublicDomain("PUBLIC2");

        // Test invalid domain names
        vm.expectRevert(abi.encodeWithSelector(IBytecodeRepository.InvalidDomainException.selector, bytes32("")));
        vm.prank(owner);
        bcr.addPublicDomain("");

        vm.expectRevert(
            abi.encodeWithSelector(IBytecodeRepository.InvalidDomainException.selector, bytes32("INVALID::DOMAIN"))
        );
        vm.prank(owner);
        bcr.addPublicDomain("INVALID::DOMAIN");

        // Test adding new public domain
        assertFalse(bcr.isPublicDomain("PUBLIC2"));

        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.AddPublicDomain(bytes32("PUBLIC2"));

        vm.prank(owner);
        bcr.addPublicDomain("PUBLIC2");

        assertTrue(bcr.isPublicDomain("PUBLIC2"));

        // Test adding domain that is already marked as system
        vm.expectRevert(
            abi.encodeWithSelector(
                IBytecodeRepository.DomainIsAlreadyMarkedAsSystemException.selector, bytes32("SYSTEM")
            )
        );
        vm.prank(owner);
        bcr.addPublicDomain("SYSTEM");
    }

    // ---------------------------- //
    // TOKEN SPECIFIC POSTFIX TESTS //
    // ---------------------------- //

    /// @notice U:[BCR-22]: Token specific postfix management works correctly
    function test_U_BCR_22_token_specific_postfix_management_works_correctly() public {
        address token = makeAddr("Token");
        bytes32 postfix = "TEST";

        // Only owner can set postfix
        vm.expectRevert(
            abi.encodeWithSelector(IImmutableOwnableTrait.CallerIsNotOwnerException.selector, address(this))
        );
        bcr.setTokenSpecificPostfix(token, postfix);

        assertEq(bcr.getTokenSpecificPostfix(token), bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.SetTokenSpecificPostfix(token, postfix);

        vm.prank(owner);
        bcr.setTokenSpecificPostfix(token, postfix);

        assertEq(bcr.getTokenSpecificPostfix(token), postfix);

        // Cannot set invalid postfix
        vm.expectRevert(
            abi.encodeWithSelector(IBytecodeRepository.InvalidPostfixException.selector, bytes32("TEST:INVALID"))
        );
        vm.prank(owner);
        bcr.setTokenSpecificPostfix(token, "TEST:INVALID");

        // Setting same postfix should be no-op
        vm.prank(owner);
        bcr.setTokenSpecificPostfix(token, postfix);

        // Can change postfix
        bytes32 newPostfix = "";
        vm.expectEmit(true, true, true, true);
        emit IBytecodeRepository.SetTokenSpecificPostfix(token, newPostfix);

        vm.prank(owner);
        bcr.setTokenSpecificPostfix(token, newPostfix);

        assertEq(bcr.getTokenSpecificPostfix(token), newPostfix);
    }

    // --------- //
    // INTERNALS //
    // --------- //

    function _getTestAuditReport(bytes32 bytecodeHash) internal returns (AuditReport memory auditReport) {
        auditReport = AuditReport({
            auditor: auditor.addr,
            reportUrl: "https://github.com/Gearbox-protocol/security",
            signature: ""
        });
        auditReport.signature = _signAuditReport(auditor, bytecodeHash, auditReport);
    }

    function _getTestBytecode(bytes32 contractType, uint256 version) internal returns (Bytecode memory bytecode) {
        bytecode = Bytecode({
            contractType: contractType,
            version: version,
            initCode: type(MockContract).creationCode,
            author: author.addr,
            source: "https://github.com/Gearbox-protocol/permissionless",
            authorSignature: ""
        });
        bytecode.authorSignature = _signBytecode(author, bytecode);
    }

    function _signAuditReport(VmSafe.Wallet memory wallet, bytes32 bytecodeHash, AuditReport memory auditReport)
        internal
        returns (bytes memory)
    {
        bytes32 auditReportHash = bcr.computeAuditReportHash(bytecodeHash, auditReport);
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(wallet, ECDSA.toTypedDataHash(bcr.domainSeparatorV4(), auditReportHash));
        return abi.encodePacked(r, s, v);
    }

    function _signBytecode(VmSafe.Wallet memory wallet, Bytecode memory bytecode) internal returns (bytes memory) {
        bytes32 bytecodeHash = bcr.computeBytecodeHash(bytecode);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wallet, ECDSA.toTypedDataHash(bcr.domainSeparatorV4(), bytecodeHash));
        return abi.encodePacked(r, s, v);
    }
}
