// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

// solhint-disable no-console
import {console2} from "forge-std/console2.sol";

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {PriceFormatter} from "silo-core/deploy/lib/PriceFormatter.sol";

import {CommonDeploy} from "../CommonDeploy.sol";
import {OraclesDeployments} from "../OraclesDeployments.sol";
import {SiloOraclesFactoriesContracts} from "../SiloOraclesFactoriesContracts.sol";
import {CustomMethodOracleFactory} from "silo-oracles/contracts/custom-method/CustomMethodOracleFactory.sol";
import {ICustomMethodOracle} from "silo-oracles/contracts/interfaces/ICustomMethodOracle.sol";

/*
Deploys one `CustomMethodOracle` via deployed `CustomMethodOracleFactory`.

Required env: TARGET, METHOD, BASE_TOKEN, QUOTE_TOKEN, PRICE_DECIMALS
  TARGET           — contract whose view method is staticcalled
  METHOD           — method name without `()`, e.g. `latestAnswer`
  BASE_TOKEN       — base asset (IERC20 address)
  QUOTE_TOKEN      — quote asset (IERC20 address)
  PRICE_DECIMALS   — decimals of the uint256 returned by the method

Optional env:
  EXTERNAL_SALT    — CREATE2 salt (bytes32 hex, default 0)

Example:
FOUNDRY_PROFILE=oracles \
    TARGET=0x072fB925014B45dec604A6c44f85DAf837653056 \
    METHOD=getExchangeRate \
    BASE_TOKEN=0x2d6E0e0c209D79b43f5d3D62e93D6A9f1e9317BD \
    QUOTE_TOKEN=0x0000000088827d2d103ee2d9A6b781773AE03FfB \
    PRICE_DECIMALS=8 \
    forge script silo-oracles/deploy/custom-method/CustomMethodOracleDeploy.s.sol \
    --ffi --rpc-url $RPC_INJECTIVE --broadcast --verify
 */
contract CustomMethodOracleDeploy is CommonDeploy {
    function run() public returns (ICustomMethodOracle oracle) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        address target = vm.envAddress("TARGET");
        string memory method = vm.envString("METHOD");
        IERC20Metadata baseToken = IERC20Metadata(vm.envAddress("BASE_TOKEN"));
        IERC20Metadata quoteToken = IERC20Metadata(vm.envAddress("QUOTE_TOKEN"));
        uint8 priceDecimals = uint8(vm.envUint("PRICE_DECIMALS"));
        bytes32 externalSalt = vm.envOr("EXTERNAL_SALT", bytes32(0));

        ICustomMethodOracle.DeploymentConfig memory cfg = ICustomMethodOracle.DeploymentConfig({
            baseToken: baseToken,
            quoteToken: quoteToken,
            target: target,
            callSelector: bytes4(keccak256(abi.encodePacked(string.concat(method, "()")))),
            priceDecimals: priceDecimals
        });

        string memory oracleName = string.concat("CUSTOM_METHOD_ORACLE_", method);
        address factoryAddr = getDeployedAddress(SiloOraclesFactoriesContracts.CUSTOM_METHOD_ORACLE_FACTORY);
        CustomMethodOracleFactory factory = CustomMethodOracleFactory(factoryAddr);

        vm.startBroadcast(deployerPrivateKey);

        oracle = factory.create(cfg, externalSalt);

        vm.stopBroadcast();

        OraclesDeployments.save(getChainAlias(), oracleName, address(oracle));

        console2.log("CustomMethodOracle:", address(oracle));
        console2.log("Oracle name (deployments key):", oracleName);
        console2.log("Canonical method on clone:", oracle.methodSignature());

        _qa(oracle, address(baseToken));
    }

    function _qa(ICustomMethodOracle _oracle, address _baseToken) internal view {
        uint256 oneBase = 10 ** IERC20Metadata(_baseToken).decimals();
        uint256 quote = _printQuote(ISiloOracle(address(_oracle)), _baseToken, oneBase);

        string memory baseSymbol = IERC20Metadata(_baseToken).symbol();
        string memory quoteSymbol = IERC20Metadata(ISiloOracle(address(_oracle)).quoteToken()).symbol();

        console2.log("\nQA ------------------------------:", address(_oracle));
        console2.log(string.concat("  Quote (1 ", baseSymbol, "):"));
        console2.log("   ", PriceFormatter.formatPriceInE18(quote), quoteSymbol);
    }
}
