// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./DiamondInitializerTypes.sol";

/// @dev This contract is used only once to initialize the diamond proxy.
contract DiamondInitializer {
  function initialize(
    IAccessManager _accessManager,
    address _tokenP,
    CollateralSetup[] memory _collaterals,
    RedemptionSetup memory _redemptionSetup
  )
    external
  {
    LibSetters.setAccessManager(_accessManager);

    ParallelizerStorage storage ts = s.transmuterStorage();
    ts.statusReentrant = NOT_ENTERED;
    ts.normalizer = uint128(BASE_27);
    ts.tokenP = ITokenP(_tokenP);

    // Setup each collateral
    uint256 collateralsLength = _collaterals.length;
    for (uint256 i; i < collateralsLength; i++) {
      CollateralSetup memory collateral = _collaterals[i];
      LibSetters.addCollateral(collateral.token);
      LibSetters.setOracle(collateral.token, collateral.oracleConfig);
      // Mint fees
      LibSetters.setFees(collateral.token, collateral.xMintFee, collateral.yMintFee, true);
      // Burn fees
      LibSetters.setFees(collateral.token, collateral.xBurnFee, collateral.yBurnFee, false);
      LibSetters.unpause(collateral.token, ActionType.Mint);
      LibSetters.unpause(collateral.token, ActionType.Burn);
      LibSetters.setStablecoinCap(collateral.token, 100_000_000 ether);
      if (collateral.targetMax) LibOracle.initializeOracleTarget(collateral.token);
    }

    // setRedemptionCurveParams
    if (_redemptionSetup.xRedeemFee.length > 0) {
      LibSetters.unpause(address(0), ActionType.Redeem);
      LibSetters.setRedemptionCurveParams(_redemptionSetup.xRedeemFee, _redemptionSetup.yRedeemFee);
    }
  }
}
