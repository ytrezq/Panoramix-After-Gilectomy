//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./base/ConvexStrategy.sol";

contract ConvexStrategyMainnet_aCRV is ConvexStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xBed1d474DdA97edcEB7b9af13be4cbf1Bb98A2D3); // Info -> LP Token address
    address rewardPool = address(0x93729702Bf9E1687Ae2124e191B8fFbcC0C8A0B0); // Info -> Rewards contract address
    address crv = address(0x172370d5Cd63279eFa6d502DAB29171933a610AF);
    address cvx = address(0x4257EA7637c355F81616050CbB6a9b709fd72683);
    address curveDeposit = address(0xd9F354177Edd66E7A6669F33d0Ec64C14E153b38);
    ConvexStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool, // rewardPool
      10,  // Pool id: Info -> Rewards contract address -> read -> pid
      crv, // depositToken
      1, //depositArrayPosition. Find deposit transaction -> input params
      curveDeposit, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
      2, //nTokens -> total number of deposit tokens
      false, //metaPool -> if LP token address == pool address (at curve)
      false //factoryPool
    );
    rewardTokens = [crv, cvx];
    reward2WETH[crv] = [crv, weth];
    reward2WETH[cvx] = [cvx, weth];
    WETH2deposit = [weth, crv];
  }
}