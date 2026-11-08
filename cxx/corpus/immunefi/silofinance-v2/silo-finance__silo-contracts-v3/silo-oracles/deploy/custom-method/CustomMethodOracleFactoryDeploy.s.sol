// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {CommonDeploy} from "../CommonDeploy.sol";
import {SiloOraclesFactoriesContracts} from "../SiloOraclesFactoriesContracts.sol";
import {CustomMethodOracleFactory} from "silo-oracles/contracts/custom-method/CustomMethodOracleFactory.sol";
import {ICustomMethodOracleFactory} from "silo-oracles/contracts/interfaces/ICustomMethodOracleFactory.sol";

/*
FOUNDRY_PROFILE=oracles \
    forge script silo-oracles/deploy/custom-method/CustomMethodOracleFactoryDeploy.s.sol \
    --ffi --rpc-url $RPC_INJECTIVE --broadcast --verify

    resume verification:
    FOUNDRY_PROFILE=oracles \
        forge script silo-oracles/deploy/custom-method/CustomMethodOracleFactoryDeploy.s.sol \
        --ffi --rpc-url https://injective.cloud.blockscout.com/api/eth-rpc \
        --verify \
        --verifier blockscout \
        --verifier-url https://injective.cloud.blockscout.com/api/ \
        --private-key $PRIVATE_KEY \
        --resume
 */
contract CustomMethodOracleFactoryDeploy is CommonDeploy {
    function run() public returns (ICustomMethodOracleFactory factory) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);

        factory = ICustomMethodOracleFactory(address(new CustomMethodOracleFactory()));

        vm.stopBroadcast();

        _registerDeployment(address(factory), SiloOraclesFactoriesContracts.CUSTOM_METHOD_ORACLE_FACTORY);
    }
}
