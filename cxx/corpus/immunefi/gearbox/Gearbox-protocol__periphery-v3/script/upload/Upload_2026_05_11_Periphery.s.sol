// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Bytecode} from "@gearbox-protocol/permissionless/contracts/interfaces/Types.sol";
import {UploadBytecode} from "@gearbox-protocol/permissionless/script/UploadBytecode.sol";

import {DefaultRWAUnderlying} from "../../contracts/rwa/DefaultRWAUnderlying.sol";
import {SecuritizeDegenNFT} from "../../contracts/rwa/SecuritizeDegenNFT.sol";
import {SecuritizeRWAFactory} from "../../contracts/rwa/SecuritizeRWAFactory.sol";

import {
    TYPE_DEFAULT_RWA_UNDERLYING,
    TYPE_SECURITIZE_DEGEN_NFT,
    TYPE_SECURITIZE_RWA_FACTORY
} from "../../contracts/libraries/AddressValidation.sol";

contract Upload_2026_05_11_Periphery is UploadBytecode {
    function _getContracts() internal pure override returns (Bytecode[] memory bytecodes) {
        bytecodes = new Bytecode[](3);
        bytecodes[0].contractType = TYPE_SECURITIZE_RWA_FACTORY;
        bytecodes[0].version = 3_10;
        bytecodes[0].initCode = type(SecuritizeRWAFactory).creationCode;
        bytecodes[0].source =
            "https://github.com/Gearbox-protocol/periphery-v3/blob/c93857d1eb8859f9b2a5e24f6261ad6599dd9b2b/contracts/rwa/SecuritizeRWAFactory.sol";

        bytecodes[1].contractType = TYPE_SECURITIZE_DEGEN_NFT;
        bytecodes[1].version = 3_10;
        bytecodes[1].initCode = type(SecuritizeDegenNFT).creationCode;
        bytecodes[1].source =
            "https://github.com/Gearbox-protocol/periphery-v3/blob/c93857d1eb8859f9b2a5e24f6261ad6599dd9b2b/contracts/rwa/SecuritizeDegenNFT.sol";

        bytecodes[2].contractType = TYPE_DEFAULT_RWA_UNDERLYING;
        bytecodes[2].version = 3_10;
        bytecodes[2].initCode = type(DefaultRWAUnderlying).creationCode;
        bytecodes[2].source =
            "https://github.com/Gearbox-protocol/periphery-v3/blob/c93857d1eb8859f9b2a5e24f6261ad6599dd9b2b/contracts/rwa/DefaultRWAUnderlying.sol";
    }
}
