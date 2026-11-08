// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {SignatureHelper} from "./SignatureHelper.sol";
import {CrossChainMultisig} from "../../../contracts/global/CrossChainMultisig.sol";
import {CrossChainCall, SignedBatch} from "../../../contracts/interfaces/ICrossChainMultisig.sol";

import {console} from "forge-std/console.sol";
import {LibString} from "@solady/utils/LibString.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

import {console2} from "forge-std/console2.sol";
import {VmSafe} from "forge-std/Vm.sol";

contract CCGHelper is SignatureHelper {
    using LibString for bytes;
    using LibString for uint256;
    // Core contracts

    VmSafe.Wallet[] internal initialSigners;

    bytes32 constant COMPACT_BATCH_TYPEHASH = keccak256("CompactBatch(string name,bytes32 batchHash,bytes32 prevHash)");

    CrossChainMultisig internal multisig;

    bytes32 public constant SALT = "SALT";

    // uint256 internal signer1Key;
    // uint256 internal signer2Key;

    // address internal signer1;
    // address internal signer2;

    address internal dao;

    bytes32 prevBatchHash;

    function _isTestMode() internal pure virtual returns (bool) {
        return false;
    }

    function _deployCCG(VmSafe.Wallet[] memory _initialSigners, uint8 _threshold, address _dao) internal {
        dao = _dao;

        uint256 length = _initialSigners.length;
        address[] memory initialSignerAddresses = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            initialSigners.push(_initialSigners[i]);
            initialSignerAddresses[i] = _initialSigners[i].addr;
        }

        multisig = new CrossChainMultisig{salt: SALT}(initialSignerAddresses, _threshold, _dao);

        prevBatchHash = 0;
    }

    function _attachCCG(address[] memory _initialSigners, uint8 _threshold, address _dao) internal {
        address ccg = computeCCGAddress(_initialSigners, _threshold, _dao);
        dao = _dao;

        if (ccg.code.length == 0) {
            revert("CCG not deployed");
        }
        multisig = CrossChainMultisig(ccg);

        prevBatchHash = multisig.lastBatchHash();
    }

    function computeCCGAddress(address[] memory _initialSigners, uint8 _threshold, address _dao)
        internal
        pure
        returns (address)
    {
        bytes memory creationCode =
            abi.encodePacked(type(CrossChainMultisig).creationCode, abi.encode(_initialSigners, _threshold, _dao));

        return
            Create2.computeAddress(SALT, keccak256(creationCode), address(0x4e59b44847b379578588920cA78FbF26c0B4956C));
    }

    function _submitBatch(string memory name, CrossChainCall[] memory calls) internal {
        _startPrankOrBroadcast(dao);
        multisig.submitBatch(name, calls, prevBatchHash);
        _stopPrankOrBroadcast();
    }

    function _signCurrentBatch() internal {
        if (initialSigners.length == 0) {
            revert("No initial signers");
        }

        bytes32[] memory currentBatchHashes = multisig.getCurrentBatchHashes();

        SignedBatch memory currentBatch = multisig.getBatch(currentBatchHashes[0]);

        bytes32 batchHash = multisig.computeBatchHash(currentBatch.name, currentBatch.calls, currentBatch.prevHash);

        bytes32 structHash = multisig.computeCompactBatchHash(currentBatch.name, batchHash, currentBatch.prevHash);

        if (!_isTestMode()) {
            console.logBytes32(structHash);
        }

        uint256 threshold = multisig.confirmationThreshold();

        for (uint256 i = 0; i < threshold; i++) {
            bytes memory signature = _sign(initialSigners[i], ECDSA.toTypedDataHash(_ccmDomainSeparator(), structHash));
            multisig.signBatch(batchHash, signature);
        }

        prevBatchHash = batchHash;
    }

    function _submitBatchAndSign(string memory name, CrossChainCall[] memory calls) internal {
        _submitBatch(name, calls);
        _signCurrentBatch();
    }

    function _ccmDomainSeparator() internal view returns (bytes32) {
        // Get domain separator from BytecodeRepository contract
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("CROSS_CHAIN_MULTISIG")),
                keccak256(bytes("310")),
                1,
                address(multisig)
            )
        );
    }
}
