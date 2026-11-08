// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Bytecode} from "@gearbox-protocol/permissionless/contracts/interfaces/Types.sol";
import {UploadBytecode} from "@gearbox-protocol/permissionless/script/UploadBytecode.sol";

import {AccountMigratorAdapterV31} from "../../contracts/migration/AccountMigratorAdapterV31.sol";
import {AccountMigratorBot} from "../../contracts/migration/AccountMigratorBot.sol";

contract Upload_2025_07_29_Periphery is UploadBytecode {
    function _getContracts() internal pure override returns (Bytecode[] memory bytecodes) {
        bytecodes = new Bytecode[](2);
        bytecodes[0].contractType = "ADAPTER::ACCOUNT_MIGRATOR";
        bytecodes[0].version = 3_10;
        bytecodes[0].initCode = type(AccountMigratorAdapterV31).creationCode;
        bytecodes[0].source =
            "https://github.com/Gearbox-protocol/periphery-v3/blob/0b1827d061f1d5340b71e6670bd3c56b47f55070/contracts/migration/AccountMigratorAdapterV31.sol";

        bytecodes[1].contractType = "BOT::ACCOUNT_MIGRATOR";
        bytecodes[1].version = 3_10;
        bytecodes[1].initCode = type(AccountMigratorBot).creationCode;
        bytecodes[1].source =
            "https://github.com/Gearbox-protocol/periphery-v3/blob/0b1827d061f1d5340b71e6670bd3c56b47f55070/contracts/migration/AccountMigratorBot.sol";
    }
}
