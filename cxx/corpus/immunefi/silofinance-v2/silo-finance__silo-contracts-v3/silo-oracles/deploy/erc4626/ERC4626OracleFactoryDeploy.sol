// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";
import {ERC4626OracleFactory} from "silo-oracles/contracts/erc4626/ERC4626OracleFactory.sol";
import {ERC4626Oracle} from "silo-oracles/contracts/erc4626/ERC4626Oracle.sol";
import {CommonDeploy} from "../CommonDeploy.sol";
import {SiloOraclesFactoriesContracts} from "../SiloOraclesFactoriesContracts.sol";

/*
    FOUNDRY_PROFILE=oracles \
        forge script silo-oracles/deploy/erc4626/ERC4626OracleFactoryDeploy.sol \
        --ffi --rpc-url $RPC_OPTIMISM --broadcast --verify

    FOUNDRY_PROFILE=oracles \
        forge script silo-oracles/deploy/erc4626/ERC4626OracleFactoryDeploy.sol \
        --ffi --rpc-url $RPC_BNB \
        --verify \
        --resume \
        --private-key $PRIVATE_KEY

    FOUNDRY_PROFILE=oracles \
        forge script silo-oracles/deploy/erc4626/ERC4626OracleFactoryDeploy.sol \
    --ffi --rpc-url $RPC_INJECTIVE \
    --verify \
    --verifier blockscout \
    --verifier-url $VERIFIER_URL_INJECTIVE \
    --private-key $PRIVATE_KEY \
    --resume
 */
contract ERC4626OracleFactoryDeploy is CommonDeploy {
    function run() public returns (address factory) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        vm.startBroadcast(deployerPrivateKey);

        factory = address(new ERC4626OracleFactory());
        // The oracle itself, so we can verify contract and future deployments will be verified as well.
        new ERC4626Oracle(IERC4626(address(1)));

        vm.stopBroadcast();

        _registerDeployment(factory, SiloOraclesFactoriesContracts.ERC4626_ORACLE_FACTORY);
    }
}
