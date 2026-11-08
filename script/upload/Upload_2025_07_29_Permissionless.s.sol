// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {RateKeeperFactory} from "../../contracts/factories/RateKeeperFactory.sol";
import {Bytecode} from "../../contracts/interfaces/Types.sol";
import {UploadBytecode} from "../UploadBytecode.sol";

contract Upload_2025_07_29_Permissionless is UploadBytecode {
    function _getContracts() internal pure override returns (Bytecode[] memory bytecodes) {
        bytecodes = new Bytecode[](1);
        bytecodes[0].contractType = "RATE_KEEPER_FACTORY";
        bytecodes[0].version = 3_11;
        bytecodes[0].initCode = type(RateKeeperFactory).creationCode;
        bytecodes[0].source =
            "https://github.com/Gearbox-protocol/permissionless/blob/4f678ac1ee24372ad6f472e3e0b3b7db2fe1e658/contracts/factories/RateKeeperFactory.sol";
    }
}
