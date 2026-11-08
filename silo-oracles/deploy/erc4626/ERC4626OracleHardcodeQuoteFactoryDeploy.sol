// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";
import {CommonDeploy} from "../CommonDeploy.sol";
import {SiloOraclesFactoriesContracts} from "../SiloOraclesFactoriesContracts.sol";

import {ERC4626OracleHardcodeQuoteFactory} from "silo-oracles/contracts/erc4626/ERC4626OracleHardcodeQuoteFactory.sol";
import {ERC4626OracleHardcodeQuote} from "silo-oracles/contracts/erc4626/ERC4626OracleHardcodeQuote.sol";

/*
    FOUNDRY_PROFILE=oracles \
        forge script silo-oracles/deploy/erc4626/ERC4626OracleHardcodeQuoteFactoryDeploy.sol \
        --ffi --rpc-url $RPC_AVALANCHE --broadcast --verify

    FOUNDRY_PROFILE=oracles \
        forge script silo-oracles/deploy/erc4626/ERC4626OracleHardcodeQuoteFactoryDeploy.sol \
        --ffi --rpc-url $RPC_INJECTIVE \
        --verify \
        --verifier blockscout \
        --verifier-url $VERIFIER_URL_INJECTIVE \
        --private-key $PRIVATE_KEY \
        --resume
 */
contract ERC4626OracleHardcodeQuoteFactoryDeploy is CommonDeploy {
    function run() public returns (address factory) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        vm.startBroadcast(deployerPrivateKey);

        factory = address(new ERC4626OracleHardcodeQuoteFactory());
        // The oracle itself, so we can verify contract and future deployments will be verified as well.
        new ERC4626OracleHardcodeQuote(IERC4626(address(1)), address(2));

        vm.stopBroadcast();

        _registerDeployment(factory, SiloOraclesFactoriesContracts.ERC4626_ORACLE_HARDCODE_QUOTE_FACTORY);
    }
}
