// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { TestBase } from "./Base.t.sol";

import { SavingsVaultIntents }       from "../src/SavingsVaultIntents.sol";
import { SavingsVaultIntentsDeploy } from "../deploy/SavingsVaultIntentsDeploy.sol";
import { SavingsVaultIntentsInit }   from "../deploy/SavingsVaultIntentsInit.sol";

contract SavingsVaultIntentsDeployTests is TestBase {

    function test_deployFull() external {
        admin   = makeAddr("admin");
        relayer = makeAddr("relayer");
        
        uint256 maxDeadlineDuration = 1 days;

        SavingsVaultIntents intentInstance = SavingsVaultIntents(
            SavingsVaultIntentsDeploy.deployFull(
                admin,
                relayer,
                maxDeadlineDuration
            )
        );

        assertEq(intentInstance.hasRole(intentInstance.DEFAULT_ADMIN_ROLE(), admin),   true);
        assertEq(intentInstance.hasRole(intentInstance.RELAYER(),            relayer), true);
        
        assertEq(intentInstance.getRoleMemberCount(intentInstance.DEFAULT_ADMIN_ROLE()), 1);
        assertEq(intentInstance.getRoleMemberCount(intentInstance.RELAYER()),            1);

        assertEq(intentInstance.maxDeadlineDuration(), maxDeadlineDuration);
    }

}


contract SavingsVaultIntentsInitTests is TestBase {

    function test_initSavingsVaultIntents() external {
        admin   = makeAddr("admin");
        relayer = makeAddr("relayer");

        uint256 maxDeadlineDuration = 1 days;

        // Step 1: Deploy SavingsIntentvault contract

        address intentsInstance = SavingsVaultIntentsDeploy.deployFull(
            admin,
            relayer,
            maxDeadlineDuration
        );

        // Step 2: Prepare init params

        SavingsVaultIntentsInit.CheckDeployParams memory checkDeployParams = 
            SavingsVaultIntentsInit.CheckDeployParams(admin, relayer, maxDeadlineDuration);

        SavingsVaultIntentsInit.ConfigVaultParams[] memory configVaultParams =
            new SavingsVaultIntentsInit.ConfigVaultParams[](2);

        configVaultParams[0] = SavingsVaultIntentsInit.ConfigVaultParams({
            vault           : address(sparkVaultUSDC),
            whitelist       : true,
            minIntentAssets : MIN_INTENT_ASSETS_USDC,
            maxIntentAssets : MAX_INTENT_ASSETS_USDC
        });

        configVaultParams[1] = SavingsVaultIntentsInit.ConfigVaultParams({
            vault           : address(sparkVaultETH),
            whitelist       : true,
            minIntentAssets : MIN_INTENT_ASSETS_ETH,
            maxIntentAssets : MAX_INTENT_ASSETS_ETH
        });

        // Step 3: Init SavingsIntentVault contract
        vm.startPrank(admin);

        SavingsVaultIntentsInit.initSavingsVaultIntents(
            intentsInstance,
            configVaultParams,
            checkDeployParams
        );
        
        vm.stopPrank();

        // Step 4: Assert init values

        (
            bool    whitelisted,
            uint256 minIntentAssets,
            uint256 maxIntentAssets
        ) = SavingsVaultIntents(intentsInstance).vaultConfig(address(sparkVaultUSDC));

        assertEq(whitelisted,     true);
        assertEq(minIntentAssets, MIN_INTENT_ASSETS_USDC);
        assertEq(maxIntentAssets, MAX_INTENT_ASSETS_USDC);

        (
            whitelisted,
            minIntentAssets,
            maxIntentAssets
        ) = SavingsVaultIntents(intentsInstance).vaultConfig(address(sparkVaultETH));

        assertEq(whitelisted,     true);
        assertEq(minIntentAssets, MIN_INTENT_ASSETS_ETH);
        assertEq(maxIntentAssets, MAX_INTENT_ASSETS_ETH);
    }

}
