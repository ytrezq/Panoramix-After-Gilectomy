// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import { ITokenP } from "contracts/interfaces/ITokenP.sol";

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        ENUMS                                                      
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

enum FacetCutAction {
  Add,
  Replace,
  Remove
}

enum ManagerType {
  EXTERNAL
}

enum ActionType {
  Mint,
  Burn,
  Redeem
}

enum TrustedType {
  Updater,
  Seller
}

enum QuoteType {
  MintExactInput,
  MintExactOutput,
  BurnExactInput,
  BurnExactOutput
}

enum OracleReadType {
  CHAINLINK_FEEDS,
  EXTERNAL,
  NO_ORACLE,
  STABLE,
  WSTETH,
  CBETH,
  RETH,
  SFRXETH,
  MAX,
  MORPHO_ORACLE
}

enum OracleQuoteType {
  UNIT,
  TARGET
}

enum WhitelistType {
  BACKED
}

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    STRUCTS                                                     
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

struct Permit2Details {
  address to; // Address that will receive the funds
  uint256 nonce; // Nonce of the transaction
  bytes signature; // Permit signature of the user
}

struct AuthorizationParams {
  address from; // Payer's address (Authorizer)
  uint256 value; // Amount authorized to be transferred
  uint256 validAfter; // The time after which this is valid (unix time)
  uint256 validBefore; // The time before which this is valid (unix time)
  bytes32 nonce; // Unique nonce
  bytes signature; // EOA (r,s,v packed) or arbitrary-length EIP-1271 contract signature
}

struct FacetCut {
  address facetAddress; // Facet contract address
  FacetCutAction action; // Can be add, remove or replace
  bytes4[] functionSelectors; // Ex. bytes4(keccak256("transfer(address,uint256)"))
}

struct Facet {
  address facetAddress; // Facet contract address
  bytes4[] functionSelectors; // Ex. bytes4(keccak256("transfer(address,uint256)"))
}

struct FacetInfo {
  address facetAddress; // Facet contract address
  uint16 selectorPosition; // Position in the list of all selectors
}

struct DiamondStorage {
  bytes4[] selectors; // List of all available selectors
  mapping(bytes4 => FacetInfo) selectorInfo; // Selector to (address, position in list)
  IAccessManager accessManager; // Contract handling access management
}

struct ImplementationStorage {
  address implementation; // Dummy implementation address for Etherscan usability
}

struct ManagerStorage {
  IERC20[] subCollaterals; // Subtokens handled by the manager or strategies
  bytes config; // Additional configuration data
}

struct Collateral {
  uint8 isManaged; // If the collateral is managed through external strategies
  uint8 isMintLive; // If minting from this asset is unpaused
  uint8 isBurnLive; // If burning to this asset is unpaused
  uint8 decimals; // IERC20Metadata(collateral).decimals()
  uint8 onlyWhitelisted; // If only whitelisted addresses can burn or redeem for this token
  uint216 normalizedStables; // Normalized amount of stablecoins issued from this collateral
  uint64[] xFeeMint; // Increasing exposures in [0,BASE_9[
  int64[] yFeeMint; // Mint fees at the exposures specified in `xFeeMint`
  uint64[] xFeeBurn; // Decreasing exposures in ]0,BASE_9]
  int64[] yFeeBurn; // Burn fees at the exposures specified in `xFeeBurn`
  bytes oracleConfig; // Data about the oracle used for the collateral
  bytes whitelistData; // For whitelisted collateral, data used to verify whitelists
  ManagerStorage managerData; // For managed collateral, data used to handle the strategies
  uint256 stablecoinCap; // Cap on the amount of stablecoins that can be issued from this collateral
}

struct ParallelizerStorage {
  ITokenP tokenP; // tokenP handled by the system
  uint8 isRedemptionLive; // If redemption is unpaused
  uint8 statusReentrant; // If call is reentrant or not
  bool consumingSchedule; // If the contract is consuming a scheduled operation
  uint128 normalizedStables; // Normalized amount of stablecoins issued by the system
  uint128 normalizer; // To reconcile `normalizedStables` values with the actual amount
  address[] collateralList; // List of collateral assets supported by the system
  uint64[] xRedemptionCurve; // Increasing collateral ratios > 0
  int64[] yRedemptionCurve; // Value of the redemption fees at `xRedemptionCurve`
  mapping(address => Collateral) collaterals; // Maps a collateral asset to its parameters
  mapping(address => uint256) isTrusted; // If an address is trusted to update the normalizer value
  mapping(address => uint256) isSellerTrusted; // If an address is trusted to sell accruing reward tokens or to run
    // keeper jobs on oracles
  mapping(WhitelistType => mapping(address => uint256)) isWhitelistedForType; // Whether an address is whitelisted for
    // a specific whitelist type
  // Used for the surplus distribution
  mapping(address => uint256) slippageTolerance;
  uint64 surplusBufferRatio; // Minimum collateral ratio required after surplus processing
  uint256 lastReleasedAt;
  uint256 totalShares; // The total shares of the totalShares for all payees
  address[] payees; // The addresses of the payees
  mapping(address => uint256) shares; // The shares of the totalShares for each payee
  // Aggregator or DEX the `RewardHandler` forwards its swap payload to
  address swapRouter;
}
