// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { console2 as console, Test, Vm } from "../../modules/forge-std/src/Test.sol";

import { MplUserActions } from "../../contracts/MplUserActions.sol";
import { SyrupDrip }      from "../../contracts/SyrupDrip.sol";

contract ValidateDeployContracts is Test {

    address globals        = 0x804a6F5F667170F545Bf14e5DDB48C70B788390C;
    address migrator       = 0x9c9499edD0cd2dCBc3C9Dd5070bAf54777AD8F2C;
    address syrup          = 0x643C4E15d7d62Ad0aBeC4a9BD4b001aA3Ef52d66;
    address stSyrup        = 0xc7E8b36E0766D9B04c93De68A9D47dD11f260B45;
    address mpl            = 0x33349B282065b0284d756F0577FB39c158F935e6;
    address xmpl           = 0x4937A209D4cDbD3ecD48857277cfd4dA4D82914c;
    address syrupDrip      = 0x509712F368255E92410893Ba2E488f40f7E986EA;
    address mplUserActions = 0x75B7B44dCD28df0beda913Ae2809ede986e8F461;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
    }

    function run() external view {
        // Asset storage variables for MPLUserActions
        require(MplUserActions(mplUserActions).migrator() == migrator, "MUA: migrator");
        require(MplUserActions(mplUserActions).mpl()      == mpl,      "MUA: mpl");
        require(MplUserActions(mplUserActions).syrup()    == syrup,    "MUA: syrup");
        require(MplUserActions(mplUserActions).xmpl()     == xmpl,     "MUA: xmpl");
        require(MplUserActions(mplUserActions).stsyrup()  == stSyrup,  "MUA: stsyrup");

        // Asset storage variables for SyrupDrip
        require(SyrupDrip(syrupDrip).asset()       == syrup,   "SD: syrup");
        require(SyrupDrip(syrupDrip).globals()     == globals, "SD: globals");
        require(SyrupDrip(syrupDrip).stakedSyrup() == stSyrup, "SD: stSyrup");
    }

}
