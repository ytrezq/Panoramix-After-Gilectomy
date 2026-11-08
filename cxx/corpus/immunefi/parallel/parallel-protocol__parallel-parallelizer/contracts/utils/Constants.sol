// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { ICbETH } from "contracts/interfaces/external/coinbase/ICbETH.sol";
import { ISfrxETH } from "contracts/interfaces/external/frax/ISfrxETH.sol";
import { IStETH } from "contracts/interfaces/external/lido/IStETH.sol";
import { IRETH } from "contracts/interfaces/external/rocketPool/IRETH.sol";

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 STORAGE SLOTS
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

/// @dev Storage position of `DiamondStorage` structure
/// @dev Equals `keccak256("diamond.standard.diamond.storage") - 1`
bytes32 constant DIAMOND_STORAGE_POSITION = 0xc8fcad8db84d3cc18b4c41d551ea0ee66dd599cde068d998e57d5e09332c131b;

/// @dev Storage position of `ParallelizerStorage` structure
/// @dev Equals `keccak256("diamond.standard.parallelizer.storage") - 1`
bytes32 constant TRANSMUTER_STORAGE_POSITION = 0x4b2dd303f68b99d244b702089c802b6e9ea1b5d4ef61fd436d6c41abb1178c75;

/// @dev Storage position of `ImplementationStorage` structure
/// @dev Equals `keccak256("eip1967.proxy.implementation") - 1`
bytes32 constant IMPLEMENTATION_STORAGE_POSITION = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                     MATHS
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

uint256 constant BASE_6 = 1e6;
uint256 constant BASE_8 = 1e8;
uint256 constant BASE_9 = 1e9;
uint256 constant BASE_12 = 1e12;
uint256 constant BPS = 1e14;
uint256 constant BASE_18 = 1e18;
uint256 constant HALF_BASE_27 = 1e27 / 2;
uint256 constant BASE_27 = 1e27;
uint256 constant BASE_36 = 1e36;
uint256 constant MAX_BURN_FEE = 999_000_000;
uint256 constant MAX_MINT_FEE = BASE_12 - 1;
uint256 constant MAX_PAYEES = 10;
uint256 constant SECONDS_PER_YEAR = 365 days;
uint256 constant MAX_STORED_ASSETS_INIT_STALENESS = 30 minutes;
/// @dev Largest relative increase a single `updateOracle` ratchet may apply to a MAX target price
uint256 constant MAX_ORACLE_RATCHET_STEP = 5e16;

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                     REENTRANT
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

// The values being non-zero value makes deployment a bit more expensive,
// but in exchange the refund on every call to nonReentrant will be lower in
// amount. Since refunds are capped to a percentage of the total
// transaction's gas, it is best to keep them low in cases like this one, to
// increase the likelihood of the full refund coming into effect.
uint8 constant NOT_ENTERED = 1;
uint8 constant ENTERED = 2;

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                     REENTRANT
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

// Role IDs for the AccessManager
uint64 constant GOVERNOR_ROLE = 10;
uint64 constant GUARDIAN_ROLE = 20;
uint64 constant KEEPER_ROLE = 30;

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                               COMMON ADDRESSES
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

address constant PERMIT_2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
ICbETH constant CBETH = ICbETH(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704);
IRETH constant RETH = IRETH(0xae78736Cd615f374D3085123A210448E74Fc6393);
IStETH constant STETH = IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
ISfrxETH constant SFRXETH = ISfrxETH(0xac3E018457B222d93114458476f3E3416Abbe38F);
address constant XEVT = 0x3Ee320c9F73a84D1717557af00695A34b26d1F1d;
address constant USDM = 0x59D9356E565Ab3A36dD77763Fc0d87fEaf85508C;
address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
address constant EURC = 0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c;
