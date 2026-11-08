// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/Script.sol";
import {BatchScript} from "forge-safe/src/BatchScript.sol";
import {AaveV3ATokenWrapper} from "../src/AaveV3ATokenWrapper.sol";
import {IRewardsController, IPool as IAaveV3Pool} from "aave-v3/extensions/stata-token/StataTokenV2.sol";
import {AToken} from "aave-v3/protocol/tokenization/AToken.sol";
import {IAToken} from "aave-v3/interfaces/IAToken.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface ICollateralVaultFactory {
    function EVC() external view returns (address);
}

/// @title UpgradeAaveV3ATokenWrapper
/// @notice Two-phase upgrade script matching the CollateralVaultFactory upgrade pattern.
contract UpgradeAaveV3ATokenWrapper is BatchScript {
    uint256 PHASE = 1; // intentionally invalid; set to 0 or 1 before running

    address aavePool;
    address wsteth;
    address deployer;
    address SAFE;
    address collateralVaultFactory;
    address evc;

    AaveV3ATokenWrapper wrapper;

    error UnknownProfile();
    error WrapperFactoryMismatch(address actualFactory);
    error WrapperEVCMismatch(address actualEVC);
    error FactoryEVCMismatch(address actualEVC);
    error ZeroPhase1Wrapper(uint256 index);

    function run() public {
        require(PHASE <= 1, "PHASE not set correctly");

        deployer = vm.envAddress("DEPLOYER_ADDRESS");
        SAFE = 0x8C54cb62900Ec252E7992C85a5b7078A8AF4Fd7F;

        loadChainAddresses();
        loadDeploymentAddresses();

        console2.log("block.chainid", uint256(block.chainid));
        console2.log("phase0 wrapper", address(wrapper));
        console2.log("SAFE", SAFE);

        if (PHASE == 0) {
            phase0();
        } else if (PHASE == 1) {
            phase1();
        } else {
            revert("PHASE not set correctly");
        }
    }

    function loadChainAddresses() internal {
        if (block.chainid == 1) {
            // Ethereum Mainnet
            aavePool = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
            wsteth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        } else if (block.chainid == 8453) {
            // Base
            aavePool = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
            wsteth = 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452;
        } else {
            revert UnknownProfile();
        }
    }

    function loadDeploymentAddresses() internal {
        string memory addressesJson = vm.readFile(_deploymentAddressesPath());
        wrapper = AaveV3ATokenWrapper(vm.parseJsonAddress(addressesJson, ".aTokenWrappers.awstETH"));
        collateralVaultFactory = vm.parseJsonAddress(addressesJson, ".collateralVaultFactory");
        evc = vm.parseJsonAddress(addressesJson, ".evc");

        validateWrapperConfig(wrapper);
        require(
            ICollateralVaultFactory(collateralVaultFactory).EVC() == evc,
            FactoryEVCMismatch(ICollateralVaultFactory(collateralVaultFactory).EVC())
        );
    }

    function phase0() internal {
        require(wrapper.version() == 2, "wrapper must be V2");

        IAaveV3Pool aavePoolContract = IAaveV3Pool(aavePool);
        address wstethAToken = aavePoolContract.getReserveData(wsteth).aTokenAddress;
        require(IAToken(wstethAToken).UNDERLYING_ASSET_ADDRESS() == wsteth, "underlying asset not correct");

        vm.startBroadcast(deployer);

        address newImpl = address(
            new AaveV3ATokenWrapper(
                evc,
                collateralVaultFactory,
                aavePoolContract,
                IRewardsController(address(AToken(wstethAToken).REWARDS_CONTROLLER()))
            )
        );

        vm.label(newImpl, "newAaveV3ATokenWrapperImpl");
        console2.log("deployed new impl for AaveV3ATokenWrapper", newImpl);
        require(AaveV3ATokenWrapper(newImpl).version() == 3, "Invalid deployment");

        string memory deploymentJson = "deployment";
        string memory finalJson = vm.serializeAddress(deploymentJson, "newImpl", newImpl);

        vm.stopBroadcast();

        string memory fileName = string.concat("UpgradeAaveV3ATokenWrapperPhase0_", vm.toString(block.chainid), ".json");
        vm.writeJson(finalJson, fileName);
        console2.log("Deployment data serialized to:", fileName);
    }

    function phase1() internal isBatch(SAFE) {
        address[] memory wrapperAddresses = new address[](3);
        wrapperAddresses[0] = 0xFaBA8f777996C0C28fe9e6554D84cB30ca3e1881;
        wrapperAddresses[1] = 0x223d402b82D6b5c4f0B9bc0348960098228139EF;
        wrapperAddresses[2] = 0x106aC75D7cc134aF2F98aC4715F9B4289FfE8DeF;

        string memory fileName = string.concat("UpgradeAaveV3ATokenWrapperPhase0_", vm.toString(block.chainid), ".json");
        string memory json = vm.readFile(fileName);
        address deployedNewImpl = vm.parseJsonAddress(json, ".newImpl");
        require(deployedNewImpl != address(0), "Missing newImpl in phase0 json");

        console2.log("phase1 wrapper count", wrapperAddresses.length);
        console2.log("new implementation", deployedNewImpl);

        for (uint256 i; i < wrapperAddresses.length; ++i) {
            address wrapperAddress = wrapperAddresses[i];
            if (wrapperAddress == address(0)) revert ZeroPhase1Wrapper(i);

            AaveV3ATokenWrapper phase1Wrapper = AaveV3ATokenWrapper(wrapperAddress);
            validateWrapperConfig(phase1Wrapper);

            if (phase1Wrapper.version() == 2) {
                bytes memory updateUUPSTxn = abi.encodeCall(
                    UUPSUpgradeable.upgradeToAndCall,
                    (deployedNewImpl, abi.encodeCall(AaveV3ATokenWrapper.setAdmin, (SAFE)))
                );
                addToBatch(wrapperAddress, updateUUPSTxn);
                console2.log("queued upgradeToAndCall for wrapper", wrapperAddress);

                bytes memory setPauseGuardianTxn = abi.encodeCall(AaveV3ATokenWrapper.setPauseGuardian, (SAFE));
                addToBatch(wrapperAddress, setPauseGuardianTxn);
                console2.log("queued setPauseGuardian for wrapper", wrapperAddress);
            } else {
                verifyUpgradedWrapper(phase1Wrapper);
                console2.log("wrapper already upgraded", wrapperAddress);
            }
        }

        executeBatch(true);
    }

    function validateWrapperConfig(AaveV3ATokenWrapper wrapperToValidate) internal view {
        require(
            address(wrapperToValidate.collateralVaultFactory()) == collateralVaultFactory,
            WrapperFactoryMismatch(address(wrapperToValidate.collateralVaultFactory()))
        );
        require(wrapperToValidate.EVC() == evc, WrapperEVCMismatch(wrapperToValidate.EVC()));
    }

    function verifyUpgradedWrapper(AaveV3ATokenWrapper wrapperToVerify) internal view {
        require(wrapperToVerify.version() == 3, "Unexpected wrapper version (must be 2 or 3)");
        require(wrapperToVerify.owner() == SAFE, "wrapper owner incorrect");
        require(wrapperToVerify.admin() == SAFE, "wrapper admin incorrect");
        require(wrapperToVerify.pauseGuardian() == SAFE, "wrapper pauseGuardian incorrect");
    }

    function _deploymentAddressesPath() internal view returns (string memory) {
        if (block.chainid == 1) {
            return "TwyneAddresses_current_1.json";
        }
        if (block.chainid == 8453) {
            return "../tech-notes/base-test-addresses/TwyneAddresses_current_8453.json";
        }
        revert UnknownProfile();
    }
}
