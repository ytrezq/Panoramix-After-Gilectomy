// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Fixture } from "../Fixture.sol";
import { OracleReadType } from "contracts/parallelizer/Storage.sol";
import "contracts/utils/Constants.sol";
import "contracts/utils/Errors.sol" as Errors;

/// @notice The redemption output list is rebuilt from the live `collateralList`, while `minAmountOuts`
/// is positional. A revoke (swap and pop) followed by an add preserves the length but reshuffles the
/// tokens, so a caller's minima would end up guarding tokens they never quoted.
contract Test_RedemptionTokenBinding is Fixture {
  uint256 internal redeemAmount;

  function setUp() public override {
    super.setUp();

    // eurB stays unbacked so governance is allowed to revoke it
    _mintExactInput(alice, address(eurA), 100 * BASE_6, 0);
    _mintExactInput(alice, address(eurY), 100 * BASE_18, 0);

    uint64[] memory xRedemption = new uint64[](1);
    int64[] memory yRedemption = new int64[](1);
    yRedemption[0] = int64(int256(BASE_9));
    hoax(guardian);
    parallelizer.setRedemptionCurveParams(xRedemption, yRedemption);

    redeemAmount = tokenP.balanceOf(alice) / 4;
  }

  function _tokensHash() internal view returns (bytes32) {
    (address[] memory tokens,) = parallelizer.quoteRedemptionCurve(redeemAmount);
    return keccak256(abi.encodePacked(tokens));
  }

  /// @dev Revoking eurB pops eurY into its slot, and adding eurB back appends it: same length,
  /// different order
  function _rotateCollateral() internal {
    (
      OracleReadType oracleType,
      OracleReadType targetType,
      bytes memory oracleData,
      bytes memory targetData,
      bytes memory hyperparameters
    ) = parallelizer.getOracle(address(eurB));

    hoax(governor);
    parallelizer.revokeCollateral(address(eurB), true);
    hoax(governor);
    parallelizer.addCollateral(address(eurB));
    hoax(governor);
    parallelizer.setOracle(
      address(eurB), abi.encode(oracleType, targetType, oracleData, targetData, hyperparameters)
    );
  }

  function test_Redeem_SucceedsWhenTheOutputListMatches() public {
    uint256[] memory minAmountOuts = new uint256[](3);
    bytes32 quotedHash = _tokensHash();

    vm.prank(alice);
    (address[] memory tokens,) =
      parallelizer.redeem(redeemAmount, alice, block.timestamp + 1 days, minAmountOuts, quotedHash);

    assertEq(tokens.length, 3);
  }

  function test_RevertWhen_CollateralRotationReordersTheOutputList() public {
    bytes32 quotedHash = _tokensHash();
    (address[] memory quotedTokens,) = parallelizer.quoteRedemptionCurve(redeemAmount);

    _rotateCollateral();

    (address[] memory liveTokens,) = parallelizer.quoteRedemptionCurve(redeemAmount);
    assertEq(liveTokens.length, quotedTokens.length, "the rotation must preserve the length");
    assertNotEq(liveTokens[1], quotedTokens[1], "the rotation must reorder the list");

    uint256[] memory minAmountOuts = new uint256[](3);
    vm.prank(alice);
    vm.expectRevert(Errors.UnexpectedRedemptionTokens.selector);
    parallelizer.redeem(redeemAmount, alice, block.timestamp + 1 days, minAmountOuts, quotedHash);
  }

  /// @dev A signature stays executable for its whole validity window, so a relayer could otherwise
  /// hold one until governance reshuffles the list
  function test_RevertWhen_AuthorizationOutlivesTheOutputList() public {
    uint256 deadline = block.timestamp + 1 hours;
    uint256[] memory minOuts = new uint256[](3);
    address[] memory forfeit = new address[](0);
    bytes32 quotedHash = _tokensHash();

    bytes memory authData =
      _buildRedeemAuth(1, alice, redeemAmount, alice, deadline, minOuts, forfeit, quotedHash, bytes32("rotate"));

    _rotateCollateral();

    // The relayer cannot satisfy the on-chain check with what was signed
    vm.prank(bob);
    vm.expectRevert(Errors.UnexpectedRedemptionTokens.selector);
    parallelizer.redeemWithAuthorization(redeemAmount, alice, deadline, minOuts, forfeit, quotedHash, authData);

    // Nor swap in the live list, which no longer derives the signed nonce
    bytes32 liveHash = _tokensHash();
    vm.prank(bob);
    vm.expectRevert(bytes("invalid signature"));
    parallelizer.redeemWithAuthorization(redeemAmount, alice, deadline, minOuts, forfeit, liveHash, authData);
  }
}
