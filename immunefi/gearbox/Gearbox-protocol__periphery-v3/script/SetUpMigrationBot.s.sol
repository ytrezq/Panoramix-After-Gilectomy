// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {IBytecodeRepository} from "@gearbox-protocol/permissionless/contracts/interfaces/IBytecodeRepository.sol";
import {Domain} from "@gearbox-protocol/permissionless/contracts/libraries/Domain.sol";

import {AccountMigratorBot} from "../contracts/migration/AccountMigratorBot.sol";
import {AccountMigratorPreviewer} from "../contracts/migration/AccountMigratorPreviewer.sol";

import {IConvexV1BaseRewardPoolAdapter} from
    "@gearbox-protocol/integrations-v3/contracts/interfaces/convex/IConvexV1BaseRewardPoolAdapter.sol";
import {IStakingRewardsAdapter} from
    "@gearbox-protocol/integrations-v3/contracts/interfaces/sky/IStakingRewardsAdapter.sol";

import {console} from "forge-std/console.sol";

address constant stkcvxRLUSD_USDC = 0x444FA0ffb033265591895b66c81c2e5fF606E097;
address constant stkcvxllamathena = 0x72eD19788Bce2971A5ed6401662230ee57e254B7;
address constant stkUSDS = 0xcB5D10A57Aeb622b92784D53F730eE2210ab370E;

address constant stkcvxRLUSD_USDC_new = 0x87FA6c0296c986D1C901d72571282D57916B964a;
address constant stkcvxllamathena_new = 0xB5528130B1d5D24aD172bF54CeeD062232AfbFBe;
address constant stkUSDS_new = 0x00F7C0d39B05089e93858A82439EA17dE7160B5a;

address constant cvxRLUSD_USDC = 0xBd5D4c539B3773086632416A4EC8ceF57c945319;
address constant cvxllamathena = 0x237926E55f9deee89833a42dEb92d3a6970850B4;
address constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

contract SetUpMigrationBot is Script {
    address constant mcFactory = 0x7D60CfaF7c2cec210638A5e46E4000894830C034;
    address constant router = 0x00aDE38841AB8c6e236E232041e43B41d74B8B45;
    address constant ioProxy = 0xBcD875f0D62B9AA22481c81975F9AE1753Fc559A;
    address contractsRegisterOld;
    VmSafe.Wallet deployer;

    bool setUpOverrides;

    function run() external {
        contractsRegisterOld = vm.envAddress("CONTRACTS_REGISTER_OLD");
        setUpOverrides = vm.envBool("SET_UP_OVERRIDES");

        deployer = vm.createWallet(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        vm.startBroadcast(deployer.privateKey);
        AccountMigratorBot accountMigratorBot = new AccountMigratorBot(mcFactory, deployer.addr, contractsRegisterOld);
        AccountMigratorPreviewer accountMigratorPreviewer =
            new AccountMigratorPreviewer(address(accountMigratorBot), router);

        if (setUpOverrides) {
            accountMigratorBot.setPhantomTokenOverride(
                stkcvxRLUSD_USDC,
                stkcvxRLUSD_USDC_new,
                cvxRLUSD_USDC,
                abi.encodeCall(IConvexV1BaseRewardPoolAdapter.withdrawDiff, (0, false))
            );

            accountMigratorBot.setPhantomTokenOverride(
                stkcvxllamathena,
                stkcvxllamathena_new,
                cvxllamathena,
                abi.encodeCall(IConvexV1BaseRewardPoolAdapter.withdrawDiff, (0, false))
            );

            accountMigratorBot.setPhantomTokenOverride(
                stkUSDS, stkUSDS_new, USDS, abi.encodeCall(IStakingRewardsAdapter.withdrawDiff, (0))
            );
        }

        accountMigratorBot.transferOwnership(ioProxy);
        vm.stopBroadcast();

        console.log("AccountMigratorBot deployed to", address(accountMigratorBot));
        console.log("AccountMigratorPreviewer deployed to", address(accountMigratorPreviewer));
    }
}
