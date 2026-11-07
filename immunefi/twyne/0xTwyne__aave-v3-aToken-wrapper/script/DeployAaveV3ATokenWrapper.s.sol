// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {AaveV3ATokenWrapper} from "../src/AaveV3ATokenWrapper.sol";
import {IRewardsController, IPool as IAaveV3Pool} from "aave-v3/extensions/stata-token/StataTokenV2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AToken} from "aave-v3/protocol/tokenization/AToken.sol";
import {IAToken} from "aave-v3/interfaces/IAToken.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface ICollateralVaultFactory {
    function EVC() external view returns (address);
    function owner() external view returns (address);
}

/// @title DeployAaveV3ATokenWrapper
/// @notice Two-phase deployment so a new wrapper can reuse an existing implementation
///         instead of redeploying it.
///
///         - PHASE 0 : deploy the implementation and record it in the deployment json.
///         - PHASE 1 : deploy a proxy pointing at the implementation from the json.
contract DeployAaveV3ATokenWrapper is Script {
    uint256 PHASE = 2; // intentionally invalid; set to 0 or 1 before running

    // Chain-specific addresses
    address aavePool;
    address ptToken = 0x9Bf45ab47747F4B4dD09B3C2c73953484b4eB375;

    error UnknownProfile();

    function run() external {
        require(PHASE <= 1, "PHASE not set correctly");

        loadChainAddresses();

        if (PHASE == 0) {
            phase0();
        } else {
            phase1();
        }
    }

    /// @notice PHASE 0: deploy the implementation and record it in the deployment json.
    function phase0() internal {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");

        vm.startBroadcast(deployer);
        address implementation = _deployImplementation();
        vm.stopBroadcast();

        writeImplementationToJson(implementation);
    }

    /// @notice PHASE 1: deploy a proxy pointing at the implementation from PHASE 0.
    function phase1() internal {
        string memory json = vm.readFile(deploymentFileName());
        address implementation = vm.parseJsonAddress(json, ".implementation");
        require(implementation != address(0), "missing implementation from phase0");

        address deployer = vm.envAddress("DEPLOYER_ADDRESS");

        vm.startBroadcast(deployer);
        address proxy = _deployProxy(implementation);
        vm.stopBroadcast();

        writeDeploymentToJson(proxy, implementation);
    }

    function loadChainAddresses() internal {
        if (block.chainid == 1) {
            // Ethereum Mainnet
            aavePool = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
        } else if (block.chainid == 8453) {
            // Base
            aavePool = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
            revert("only mainnet");
        } else {
            revert UnknownProfile();
        }

        console.log("Deploying on chain:", block.chainid);
        console.log("Aave Pool:", aavePool);
        console.log("PT Token:", ptToken);
    }

    /// @dev Must be called within an active broadcast.
    function _deployImplementation() internal returns (address implementation) {
        string memory addressesJson = vm.readFile("TwyneAddresses_output.json");
        address collateralVaultFactory = vm.parseJsonAddress(addressesJson, ".collateralVaultFactory");
        address evc = ICollateralVaultFactory(collateralVaultFactory).EVC();

        // Fetch PT token aToken address dynamically from Aave protocol
        IAaveV3Pool aavePoolContract = IAaveV3Pool(aavePool);
        address ptAToken = aavePoolContract.getReserveData(ptToken).aTokenAddress;
        console.log("PT aToken fetched from Aave:", ptAToken);

        // Validate that the aToken has the correct underlying asset
        require(IAToken(ptAToken).UNDERLYING_ASSET_ADDRESS() == ptToken, "underlying asset not correct");
        console.log("aToken validation: underlying asset matches PT token");

        implementation = address(new AaveV3ATokenWrapper(
            evc,
            collateralVaultFactory,
            aavePoolContract,
            IRewardsController(address(AToken(ptAToken).REWARDS_CONTROLLER()))
        ));

        console.log("Implementation Address:", implementation);
        return implementation;
    }

    /// @dev Must be called within an active broadcast.
    function _deployProxy(address implementation) internal returns (address proxy) {
        string memory addressesJson = vm.readFile("TwyneAddresses_output.json");
        address collateralVaultFactory = vm.parseJsonAddress(addressesJson, ".collateralVaultFactory");
        address SAFE = ICollateralVaultFactory(collateralVaultFactory).owner();
        address evc = ICollateralVaultFactory(collateralVaultFactory).EVC();

        IAaveV3Pool aavePoolContract = IAaveV3Pool(aavePool);
        address ptAToken = aavePoolContract.getReserveData(ptToken).aTokenAddress;

        string memory aTokenName = IERC20Metadata(ptAToken).name();
        string memory aTokenSymbol = IERC20Metadata(ptAToken).symbol();
        string memory wrapperName = string.concat("Wrapped ", aTokenName);
        string memory wrapperSymbol = string.concat("w", aTokenSymbol);

        console.log("Wrapper name:", wrapperName);
        console.log("Wrapper symbol:", wrapperSymbol);

        bytes memory initData = abi.encodeCall(
            AaveV3ATokenWrapper.initialize,
            (ptAToken, SAFE, wrapperName, wrapperSymbol)
        );

        proxy = address(new ERC1967Proxy(implementation, initData));

        logDeployment(proxy, implementation, evc, collateralVaultFactory, SAFE);
        return proxy;
    }

    function logDeployment(
        address proxy,
        address implementation,
        address evc,
        address collateralVaultFactory,
        address owner
    ) internal pure {
        console.log("===== AaveV3ATokenWrapper Deployment Complete =====");
        console.log("Proxy Address:", proxy);
        console.log("Implementation Address:", implementation);
        console.log("EVC Address:", evc);
        console.log("Collateral Vault Factory:", collateralVaultFactory);
        console.log("Owner:", owner);
        console.log("====================================");
    }

    function deploymentFileName() internal view returns (string memory) {
        string memory chainName = block.chainid == 1 ? "mainnet" : block.chainid == 8453 ? "base" : "unknown";
        return string.concat(chainName, ".json");
    }

    function writeImplementationToJson(address implementation) internal {
        string memory fileName = deploymentFileName();

        string memory json = "deployment";
        json = vm.serializeAddress(json, "implementation", implementation);

        vm.writeFile(fileName, json);
        console.log("Implementation info written to:", fileName);
    }

    function writeDeploymentToJson(address proxy, address implementation) internal {
        string memory fileName = deploymentFileName();

        string memory json = "deployment";
        vm.serializeAddress(json, "implementation", implementation);
        json = vm.serializeAddress(json, "proxy", proxy);

        vm.writeFile(fileName, json);
        console.log("Deployment info written to:", fileName);
    }
}
