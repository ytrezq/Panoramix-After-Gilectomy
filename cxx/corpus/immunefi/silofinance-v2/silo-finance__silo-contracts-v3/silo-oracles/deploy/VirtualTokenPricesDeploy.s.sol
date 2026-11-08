// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.6;

import {CommonDeploy} from "./CommonDeploy.sol";
import {VirtualTokenPrice} from "silo-oracles/contracts/VirtualTokenPrice.sol";
import {SiloOraclesContracts} from "./SiloOraclesContracts.sol";

/*
    FOUNDRY_PROFILE=oracles \
        forge script silo-oracles/deploy/VirtualTokenPricesDeploy.s.sol \
        --ffi --rpc-url $RPC_SONIC --broadcast --verify

    Resume verification:
    FOUNDRY_PROFILE=oracles \
        forge script silo-oracles/deploy/VirtualTokenPricesDeploy.s.sol \
        --ffi --rpc-url $RPC_INK \
        --verify \
        --verifier blockscout \
        --verifier-url $VERIFIER_URL_INK \
        --private-key $PRIVATE_KEY \
        --resume

    FOUNDRY_PROFILE=oracles forge verify-contract <contract-address> \
        silo-oracles/contracts/silo-virtual-assets/SiloVirtualAsset8Decimals.sol:SiloVirtualAsset8Decimals \
        --verifier blockscout \
        --verifier-url $VERIFIER_URL_INK \
        --compiler-version 0.8.28 \
        --num-of-optimizations 200 \
        --watch
 */
contract VirtualTokenPricesDeploy is CommonDeploy {
    function run() public {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        vm.startBroadcast(deployerPrivateKey);

        address virtualTokenPrice = address(new VirtualTokenPrice());

        vm.stopBroadcast();

        _registerDeployment(virtualTokenPrice, SiloOraclesContracts.VIRTUAL_TOKEN_PRICE);
    }
}
