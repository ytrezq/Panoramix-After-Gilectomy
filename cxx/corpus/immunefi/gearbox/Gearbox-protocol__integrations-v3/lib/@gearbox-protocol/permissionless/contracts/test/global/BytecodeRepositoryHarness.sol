// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {BytecodeRepository} from "../../global/BytecodeRepository.sol";
import {AuditReport, Bytecode, BytecodePointer} from "../../interfaces/Types.sol";

contract BytecodeRepositoryHarness is BytecodeRepository {
    constructor(address owner_) BytecodeRepository(owner_) {}

    function exposed_allowContract(bytes32 bytecodeHash, bytes32 cType, uint256 ver) external {
        _allowContract(bytecodeHash, cType, ver);
    }
}
