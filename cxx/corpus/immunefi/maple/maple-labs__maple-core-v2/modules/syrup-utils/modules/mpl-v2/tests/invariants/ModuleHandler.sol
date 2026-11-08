// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { IEmergencyModule }        from "../../contracts/interfaces/IEmergencyModule.sol";
import { IMapleToken }             from "../../contracts/interfaces/IMapleToken.sol";
import { IRecapitalizationModule } from "../../contracts/interfaces/IRecapitalizationModule.sol";

import { IGlobalsLike } from "../utils/Interfaces.sol";

import { console, TestBase } from "../utils/TestBase.sol";

contract ModuleHandler is TestBase {

    uint256 constant MAX_IR      = 1e18;
    uint256 constant MAX_MINT    = 1_000_000e18;
    uint256 constant MAX_START   = 365 days;
    uint256 constant MAX_WARP    = 30 days;
    uint256 constant MAX_WINDOWS = 5;

    address claimer;

    uint32 public blockTimestamp;

    IGlobalsLike mapleGlobals;
    IMapleToken  mapleToken;

    IEmergencyModule        emergencyModule;
    IRecapitalizationModule recapitalizationModule;

    mapping(address => uint256) allowances;
    mapping(address => uint256) balances;

    constructor(
        IGlobalsLike            mapleGlobals_,
        IMapleToken             mapleToken_,
        IEmergencyModule        emergencyModule_,
        IRecapitalizationModule recapitalizationModule_,
        address                 claimer_
    )
    {
        mapleGlobals           = mapleGlobals_;
        mapleToken             = mapleToken_;
        emergencyModule        = emergencyModule_;
        recapitalizationModule = recapitalizationModule_;

        claimer = claimer_;

        blockTimestamp = uint32(block.timestamp);
    }

    /**************************************************************************************************************************************/
    /*** Modifiers                                                                                                                      ***/
    /**************************************************************************************************************************************/

    modifier useBlockTimestamp() {
        vm.warp(blockTimestamp);

        _;
    }

    /**************************************************************************************************************************************/
    /*** Actions                                                                                                                        ***/
    /**************************************************************************************************************************************/

    function claim(uint256 seed) external useBlockTimestamp {
        seed;  // Unused parameter

        console.log("claim(%s)", seed);

        // Skip if nothing is claimable.
        if (recapitalizationModule.claimable(blockTimestamp) == 0) return;

        vm.prank(claimer);
        uint256 amount = recapitalizationModule.claim();

        console.log("Amount of tokens claimed:", amount);
    }

    function emergencyBurn(uint256 seed) external useBlockTimestamp {
        console.log("emergencyBurn(%s)", seed);

        address treasury = mapleGlobals.mapleTreasury();
        uint256 balance  = mapleToken.balanceOf(treasury);

        // Skip if no tokens can be burned.
        if (balance == 0) return;

        address governor = mapleGlobals.governor();
        uint256 amount   = bound(seed, 1, balance);

        vm.prank(governor);
        emergencyModule.burn(treasury, amount);

        console.log("Amount of tokens burned:", amount);
    }

    function emergencyMint(uint256 seed) external useBlockTimestamp {
        console.log("emergencyMint(%s)", seed);

        address governor = mapleGlobals.governor();
        uint256 amount   = bound(seed, 1, MAX_MINT);

        vm.prank(governor);
        emergencyModule.mint(amount);

        console.log("Amount of tokens minted:", amount);
    }

    function schedule(uint256 seed) external useBlockTimestamp {
        console.log("schedule(%s)", seed);

        uint256 numberOfWindows = bound(seed, 1, MAX_WINDOWS);

        uint32[]  memory windowStarts  = new uint32[](numberOfWindows);
        uint208[] memory issuanceRates = new uint208[](numberOfWindows);

        uint32 minWindowStart = uint32(blockTimestamp + 7 days + 2);

        for (uint i; i < numberOfWindows; ++i) {
            uint256 windowSeed = uint256(keccak256(abi.encode(seed, i)));

            windowStarts[i]  = uint32(bound(windowSeed, minWindowStart, minWindowStart + MAX_START));
            issuanceRates[i] = uint208(bound(windowSeed, 0, MAX_IR));

            minWindowStart = windowStarts[i] + 1 seconds;

            console.log("Added a new window:", windowStarts[i], issuanceRates[i]);
        }

        address governor = mapleGlobals.governor();

        vm.prank(governor);
        mapleGlobals.scheduleCall(
            address(recapitalizationModule),
            "RM:SCHEDULE",
            abi.encodeWithSelector(recapitalizationModule.schedule.selector, windowStarts, issuanceRates)
        );

        vm.warp(blockTimestamp + 7 days + 1);

        blockTimestamp += 7 days + 1;

        vm.prank(governor);
        recapitalizationModule.schedule(windowStarts, issuanceRates);
    }

    function warp(uint256 seed) external {
        console.log("warp(%d)", seed);

        blockTimestamp += uint32(bound(seed, 1 seconds, MAX_WARP));

        console.log("Warped to timestamp:", blockTimestamp);
    }

}
