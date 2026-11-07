// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.28;

import { console } from "@forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import { Constants, ContractType } from "@helpers/Constants.sol";

import { ITokenP } from "contracts/interfaces/ITokenP.sol";
import { IManager } from "contracts/interfaces/IManager.sol";
import { AggregatorV3Interface } from "contracts/interfaces/external/chainlink/AggregatorV3Interface.sol";
import { SavingsNameable } from "contracts/savings/nameable/SavingsNameable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { CHAIN_SOURCE } from "scripts/helpers/Constants.s.sol";

import { MockAccessControlManager } from "./mock/MockAccessControlManager.sol";
import { MockChainlinkOracle } from "./mock/MockChainlinkOracle.sol";
import { MockTokenPermit } from "./mock/MockTokenPermit.sol";

import { CollateralSetup, Test } from "contracts/parallelizer/configs/Test.sol";
import "contracts/utils/Constants.sol";
import "contracts/utils/Errors.sol";
import "contracts/parallelizer/Storage.sol";
import { IParallelizer } from "contracts/interfaces/IParallelizer.sol";
import { Parallelizer } from "./utils/Parallelizer.sol";
import { ConfigAccessManager } from "./utils/ConfigAccessManager.sol";
import { SavingsUtils } from "./utils/Savings.sol";

contract Fixture is Parallelizer, SavingsUtils, ConfigAccessManager {
  ITokenP public tokenP;

  IERC20 public eurA;
  AggregatorV3Interface public oracleA;
  IERC20 public eurB;
  AggregatorV3Interface public oracleB;
  IERC20 public eurY;
  AggregatorV3Interface public oracleY;

  address public config;

  // Percentage tolerance on test - 0.0001%
  uint256 internal constant _MAX_PERCENTAGE_DEVIATION = 1e12;
  uint256 internal constant _MAX_SUB_COLLATERALS = 10;

  address public guardian;
  address public governor;
  address public governorAndGuardian;

  address public alice;
  address public bob;
  address public charlie;
  address public dylan;
  address public sweeper;
  address public treasury;

  function setUp() public virtual {
    alice = vm.addr(1);
    bob = vm.addr(2);
    charlie = vm.addr(3);
    dylan = vm.addr(4);
    sweeper = address(uint160(uint256(keccak256(abi.encodePacked("sweeper")))));
    governor = address(uint160(uint256(keccak256(abi.encodePacked("governor")))));
    guardian = address(uint160(uint256(keccak256(abi.encodePacked("guardian")))));
    governorAndGuardian = address(uint160(uint256(keccak256(abi.encodePacked("governorAndGuardian")))));
    treasury = address(uint160(uint256(keccak256(abi.encodePacked("treasury")))));

    vm.label(governor, "Governor");
    vm.label(guardian, "Guardian");
    vm.label(governorAndGuardian, "GovernorAndGuardian");
    vm.label(alice, "Alice");
    vm.label(bob, "Bob");
    vm.label(charlie, "Charlie");
    vm.label(dylan, "Dylan");
    vm.label(sweeper, "Sweeper");
    vm.label(treasury, "Treasury");

    deployAccessManager(governor, governor, guardian, governorAndGuardian);

    // tokenP
    tokenP = ITokenP(address(new MockTokenPermit("agEUR", "agEUR", 18)));

    // Collaterals
    eurA = IERC20(address(new MockTokenPermit("EUR_A", "EUR_A", 6)));
    vm.label(address(eurA), "eurA");
    oracleA = AggregatorV3Interface(address(new MockChainlinkOracle()));
    vm.label(address(oracleA), "oracleA");
    MockChainlinkOracle(address(oracleA)).setLatestAnswer(int256(BASE_8));

    eurB = IERC20(address(new MockTokenPermit("EUR_B", "EUR_B", 12)));
    vm.label(address(eurB), "eurB");
    oracleB = AggregatorV3Interface(address(new MockChainlinkOracle()));
    vm.label(address(oracleB), "oracleB");
    MockChainlinkOracle(address(oracleB)).setLatestAnswer(int256(BASE_8));

    eurY = IERC20(address(new MockTokenPermit("EUR_Y", "EUR_Y", 18)));
    vm.label(address(eurY), "eurY");
    oracleY = AggregatorV3Interface(address(new MockChainlinkOracle()));
    vm.label(address(oracleY), "oracleY");
    MockChainlinkOracle(address(oracleY)).setLatestAnswer(int256(BASE_8));

    // Config

    config = address(new Test());

    deployParallelizer(
      config,
      abi.encodeWithSelector(
        Test.initialize.selector,
        address(accessManager),
        tokenP,
        CollateralSetup(address(eurA), address(oracleA)),
        CollateralSetup(address(eurB), address(oracleB)),
        CollateralSetup(address(eurY), address(oracleY))
      )
    );

    vm.label(address(tokenP), "tokenP");
    vm.label(address(parallelizer), "Parallelizer");
    vm.label(address(eurA), "eurA");
    vm.label(address(eurB), "eurB");
    vm.label(address(eurY), "eurY");

    vm.startPrank(governor);
    accessManager.setTargetFunctionRole(address(parallelizer), getParallelizerGovernorSelectorAccess(), GOVERNOR_ROLE);
    accessManager.setTargetFunctionRole(address(parallelizer), getParallelizerGuardianSelectorAccess(), GUARDIAN_ROLE);
    accessManager.setTargetFunctionRole(address(parallelizer), getParallelizerKeeperSelectorAccess(), KEEPER_ROLE);
    vm.stopPrank();
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ASSERTIONS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  // Allow to have larger deviation for very small amounts
  function _assertApproxEqRelDecimalWithTolerance(
    uint256 a,
    uint256 b,
    uint256 condition,
    uint256 maxPercentDelta, // An 18 decimal fixed point number, where 1e18 == 100%
    uint256 decimals
  )
    internal
    virtual
  {
    for (uint256 tol = BASE_18 / maxPercentDelta; tol > 0; tol /= 10) {
      if (condition > tol) {
        assertApproxEqRelDecimal(a, b, tol == 0 ? BASE_18 : (BASE_18 / tol), decimals);
        break;
      }
    }
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ACTIONS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function _mintExactOutput(address owner, address tokenIn, uint256 amountStable, uint256 estimatedAmountIn) internal {
    vm.startPrank(owner);
    deal(tokenIn, owner, estimatedAmountIn);
    IERC20(tokenIn).approve(address(parallelizer), type(uint256).max);
    parallelizer.swapExactOutput(amountStable, estimatedAmountIn, tokenIn, address(tokenP), owner, block.timestamp * 2);
    vm.stopPrank();
  }

  function _mintExactInput(address owner, address tokenIn, uint256 amountIn, uint256 estimatedStable) internal {
    vm.startPrank(owner);
    deal(tokenIn, owner, amountIn);
    IERC20(tokenIn).approve(address(parallelizer), type(uint256).max);
    parallelizer.swapExactInput(amountIn, estimatedStable, tokenIn, address(tokenP), owner, block.timestamp * 2);
    vm.stopPrank();
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    EIP-3009 HELPERS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  bytes32 internal constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH =
    0xd099cc98ef71107a616c4f0f941f04c322d8e254fe26b3c6668db87aae413de8;

  bytes32 internal constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
    0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267;

  function _buildAuthData(
    uint256 privateKey,
    address token,
    address from,
    address to,
    uint256 value,
    bytes32 nonce
  )
    internal
    view
    returns (bytes memory)
  {
    bytes32 domainSeparator = MockTokenPermit(token).DOMAIN_SEPARATOR();
    bytes32 structHash =
      keccak256(abi.encode(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, 0, block.timestamp + 1 hours, nonce));
    bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
    return abi.encode(
      AuthorizationParams({
        from: from,
        value: value,
        validAfter: 0,
        validBefore: block.timestamp + 1 hours,
        nonce: nonce,
        signature: abi.encodePacked(r, s, v)
      })
    );
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    PARALLELIZER AUTHORIZATION HELPERS — derived-nonce scheme, mirrors `LibAuthorization`
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  bytes32 internal constant PARALLELIZER_SWAP_EXACT_INPUT_TYPEHASH = keccak256(
    "SwapExactInputWithAuthorization(address from,address tokenIn,address tokenOut,uint256 amountIn,"
    "uint256 amountOutMin,address to,uint256 deadline,bytes32 userSalt)"
  );

  bytes32 internal constant PARALLELIZER_SWAP_EXACT_OUTPUT_TYPEHASH = keccak256(
    "SwapExactOutputWithAuthorization(address from,address tokenIn,address tokenOut,uint256 amountOut,"
    "uint256 amountInMax,address to,uint256 deadline,bytes32 userSalt)"
  );

  bytes32 internal constant PARALLELIZER_REDEEM_TYPEHASH = keccak256(
    "RedeemWithAuthorization(address from,uint256 amount,address receiver,uint256 deadline,"
    "bytes32 minAmountOutsHash,bytes32 forfeitTokensHash,bytes32 expectedTokensHash,bytes32 userSalt)"
  );

  function _buildSwapExactInputAuth(
    uint256 privateKey,
    address tokenIn,
    address tokenOut,
    address from,
    uint256 amountIn,
    uint256 amountOutMin,
    address to,
    uint256 deadline,
    bytes32 userSalt
  )
    internal
    view
    returns (bytes memory)
  {
    bytes32 derivedNonce = keccak256(
      abi.encode(
        PARALLELIZER_SWAP_EXACT_INPUT_TYPEHASH, from, tokenIn, tokenOut, amountIn, amountOutMin, to, deadline, userSalt
      )
    );
    return _signAndPackAuth(privateKey, tokenIn, from, amountIn, derivedNonce, userSalt);
  }

  function _buildSwapExactOutputAuth(
    uint256 privateKey,
    address tokenIn,
    address tokenOut,
    address from,
    uint256 amountOut,
    uint256 amountInMax,
    address to,
    uint256 deadline,
    bytes32 userSalt
  )
    internal
    view
    returns (bytes memory)
  {
    bytes32 derivedNonce = keccak256(
      abi.encode(
        PARALLELIZER_SWAP_EXACT_OUTPUT_TYPEHASH,
        from,
        tokenIn,
        tokenOut,
        amountOut,
        amountInMax,
        to,
        deadline,
        userSalt
      )
    );
    return _signAndPackAuth(privateKey, tokenIn, from, amountInMax, derivedNonce, userSalt);
  }

  function _buildRedeemAuth(
    uint256 privateKey,
    address from,
    uint256 amount,
    address receiver,
    uint256 deadline,
    uint256[] memory minAmountOuts,
    address[] memory forfeitTokens,
    bytes32 expectedTokensHash,
    bytes32 userSalt
  )
    internal
    view
    returns (bytes memory)
  {
    bytes32 derivedNonce = keccak256(
      abi.encode(
        PARALLELIZER_REDEEM_TYPEHASH,
        from,
        amount,
        receiver,
        deadline,
        keccak256(abi.encodePacked(minAmountOuts)),
        keccak256(abi.encodePacked(forfeitTokens)),
        expectedTokensHash,
        userSalt
      )
    );
    return _signAndPackAuth(privateKey, address(tokenP), from, amount, derivedNonce, userSalt);
  }

  /// @dev The output list a redemption of `amount` would produce right now, hashed as the redeem
  /// entry points expect it
  function _redemptionTokensHash(uint256 amount) internal view returns (bytes32) {
    (address[] memory tokens,) = parallelizer.quoteRedemptionCurve(amount);
    return keccak256(abi.encodePacked(tokens));
  }

  /// @dev Signs an EIP-3009 `ReceiveWithAuthorization` with `nonce = signedNonce` and packs an
  /// `AuthorizationParams` whose on-the-wire `nonce` field carries `userSalt`, matching what the
  /// Parallelizer facets expect.
  function _signAndPackAuth(
    uint256 privateKey,
    address token,
    address from,
    uint256 value,
    bytes32 signedNonce,
    bytes32 userSalt
  )
    private
    view
    returns (bytes memory)
  {
    uint256 validBefore = block.timestamp + 1 hours;
    bytes32 structHash = keccak256(
      abi.encode(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, address(parallelizer), value, 0, validBefore, signedNonce)
    );
    bytes32 digest = MessageHashUtils.toTypedDataHash(MockTokenPermit(token).DOMAIN_SEPARATOR(), structHash);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
    return abi.encode(
      AuthorizationParams({
        from: from,
        value: value,
        validAfter: 0,
        validBefore: validBefore,
        nonce: userSalt,
        signature: abi.encodePacked(r, s, v)
      })
    );
  }
}
