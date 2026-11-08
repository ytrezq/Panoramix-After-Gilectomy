// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import "contracts/utils/Constants.sol";
import {
  AggregatorV3Interface, BaseActor, IERC20, IERC20Metadata, IParallelizer, TestStorage
} from "./BaseActor.t.sol";
import { QuoteType } from "contracts/parallelizer/Storage.sol";

import { console } from "@forge-std/console.sol";

contract TraderWithSplit is BaseActor {
  constructor(
    IParallelizer parallelizer,
    IParallelizer transmuterSplit,
    address[] memory collaterals,
    AggregatorV3Interface[] memory oracles,
    uint256 nbrTrader
  )
    BaseActor(nbrTrader, "Trader", parallelizer, transmuterSplit, collaterals, oracles)
  { }

  function swap(
    uint256 collatNumber,
    uint256 actionType,
    uint256 amount,
    uint256 splitProportion,
    uint256 actorIndex
  )
    public
    useActor(actorIndex)
    countCall("swap")
    returns (uint256, uint256)
  {
    QuoteType quoteType = QuoteType(bound(actionType, 0, 3));
    collatNumber = bound(collatNumber, 0, 2);
    amount = bound(amount, 1, 10 ** 12);
    {
      // if the number of stablecoins issued is null don't split the trades as in the solifity
      // we consider it as a different case by setting constant fees
      uint256 stablecoinIssued = _parallelizer.getTotalIssued();
      if (stablecoinIssued < 10 wei) splitProportion = BASE_9;
      else splitProportion = bound(splitProportion, 1, BASE_9);
    }

    address collateral = _collaterals[collatNumber];

    if (
      (quoteType == QuoteType.BurnExactInput || quoteType == QuoteType.BurnExactOutput)
        && tokenP.balanceOf(_currentActor) == 0
    ) return (0, 0);

    TestStorage memory testS;

    console.log("");
    console.log("=========");

    if (quoteType == QuoteType.MintExactInput) {
      console.log("Mint - Input");
      testS.tokenIn = collateral;
      testS.tokenOut = address(tokenP);
      testS.amountIn = amount * 10 ** IERC20Metadata(collateral).decimals();
      testS.amountOut = _parallelizer.quoteIn(testS.amountIn, testS.tokenIn, testS.tokenOut);
    } else if (quoteType == QuoteType.BurnExactInput) {
      console.log("Burn - Input");
      testS.tokenIn = address(tokenP);
      testS.tokenOut = collateral;
      // divided by 2 because we need to do for both the parallelizer and the replica
      testS.amountIn = bound(amount * BASE_18, 1, tokenP.balanceOf(_currentActor) / 2);
      testS.amountOut = _parallelizer.quoteIn(testS.amountIn, testS.tokenIn, testS.tokenOut);
    } else if (quoteType == QuoteType.MintExactOutput) {
      console.log("Mint - Output");
      testS.tokenIn = collateral;
      testS.tokenOut = address(tokenP);
      testS.amountOut = amount * BASE_18;
      testS.amountIn = _parallelizer.quoteOut(testS.amountOut, testS.tokenIn, testS.tokenOut);
    } else if (quoteType == QuoteType.BurnExactOutput) {
      console.log("Burn - Output");
      testS.tokenIn = address(tokenP);
      testS.tokenOut = collateral;
      testS.amountOut = amount * 10 ** IERC20Metadata(collateral).decimals();
      testS.amountIn = _parallelizer.quoteOut(testS.amountOut, testS.tokenIn, testS.tokenOut);
      // divided by 2 because we need to do for both the parallelizer and the replica
      uint256 actorBalance = tokenP.balanceOf(_currentActor) / 2;
      // If the actor cannot fund the requested exact-output, fall back to exact-input
      // semantics ("burn what you have"). swapExactInput consumes amountIn exactly, so the
      // post-swap balance assertion stays exact (no quoteIn/quoteOut rounding asymmetry).
      if (actorBalance < testS.amountIn) {
        quoteType = QuoteType.BurnExactInput;
        testS.amountIn = actorBalance;
        testS.amountOut = _parallelizer.quoteIn(actorBalance, testS.tokenIn, testS.tokenOut);
      }
    }

    console.log("Amount In: ", testS.amountIn);
    console.log("Amount Out: ", testS.amountOut);
    console.log("=========");
    console.log("");

    // If burning we can't burn more than the reserves
    if (quoteType == QuoteType.BurnExactInput || quoteType == QuoteType.BurnExactOutput) {
      (uint256 stablecoinsFromCollateral, uint256 totalStables) = _parallelizer.getIssuedByCollateral(collateral);
      if (
        testS.amountOut > IERC20(testS.tokenOut).balanceOf(address(_parallelizer))
          || testS.amountIn > stablecoinsFromCollateral || testS.amountIn > totalStables
      ) {
        return (0, 0);
      }
    }

    if (quoteType == QuoteType.MintExactInput || quoteType == QuoteType.MintExactOutput) {
      // Deal tokens to _currentActor if needed
      if (IERC20(testS.tokenIn).balanceOf(_currentActor) < 2 * testS.amountIn) {
        deal(testS.tokenIn, _currentActor, 2 * testS.amountIn);
      }
    }

    // Approval only usefull for QuoteType.MintExactInput and QuoteType.MintExactOutput
    IERC20(testS.tokenIn).approve(address(_parallelizer), testS.amountIn);
    IERC20(testS.tokenIn).approve(address(_parallelizerSplit), testS.amountIn + 1);

    // Swap
    if (quoteType == QuoteType.MintExactInput || quoteType == QuoteType.BurnExactInput) {
      _parallelizer.swapExactInput(
        testS.amountIn, testS.amountOut, testS.tokenIn, testS.tokenOut, _currentActor, block.timestamp + 1 hours
      );
      // send the received tokens to the sweeper
      // replicate on the other parallelizer but split the orders
      {
        testS.amountInSplit1 = (testS.amountIn * splitProportion) / BASE_9;
        testS.amountOutSplit1 = _parallelizerSplit.quoteIn(testS.amountInSplit1, testS.tokenIn, testS.tokenOut);
        _parallelizerSplit.swapExactInput(
          testS.amountInSplit1,
          testS.amountOutSplit1,
          testS.tokenIn,
          testS.tokenOut,
          sweeper,
          block.timestamp + 1 hours
        );

        testS.amountInSplit2 = testS.amountIn - testS.amountInSplit1;
        testS.amountOutSplit2 = _parallelizerSplit.quoteIn(testS.amountInSplit2, testS.tokenIn, testS.tokenOut);
        _parallelizerSplit.swapExactInput(
          testS.amountInSplit2,
          testS.amountOutSplit2,
          testS.tokenIn,
          testS.tokenOut,
          sweeper,
          block.timestamp + 1 hours
        );
      }
    } else {
      _parallelizer.swapExactOutput(
        testS.amountOut, testS.amountIn, testS.tokenIn, testS.tokenOut, _currentActor, block.timestamp + 1 hours
      );
      // replicate on the other parallelizer but wplit the orders
      {
        testS.amountOutSplit1 = (testS.amountOut * splitProportion) / BASE_9;
        testS.amountInSplit1 = _parallelizerSplit.quoteOut(testS.amountOutSplit1, testS.tokenIn, testS.tokenOut);
        {
          // We can be missing either stablecoins or amountIn in the case of BurnExactOutput and
          // MintExactOutput respectiveley
          // Making revert the tx due to rounding errors. We increase balances have non reverting txs
          uint256 actorBalance = tokenP.balanceOf(_currentActor);
          if (quoteType == QuoteType.BurnExactOutput && actorBalance < testS.amountInSplit1) {
            testS.amountInSplit1 = actorBalance;
            testS.amountOutSplit1 = _parallelizerSplit.quoteIn(testS.amountInSplit1, testS.tokenIn, testS.tokenOut);
          } else if (
            quoteType == QuoteType.MintExactOutput
              && IERC20(testS.tokenIn).balanceOf(_currentActor) < testS.amountInSplit1
          ) {
            deal(testS.tokenIn, _currentActor, testS.amountInSplit1);
            IERC20(testS.tokenIn).approve(address(_parallelizerSplit), testS.amountInSplit1);
          }
        }
        _parallelizerSplit.swapExactOutput(
          testS.amountOutSplit1,
          testS.amountInSplit1,
          testS.tokenIn,
          testS.tokenOut,
          sweeper,
          block.timestamp + 1 hours
        );

        testS.amountOutSplit2 = testS.amountOut - testS.amountOutSplit1;
        testS.amountInSplit2 = _parallelizerSplit.quoteOut(testS.amountOutSplit2, testS.tokenIn, testS.tokenOut);
        {
          uint256 actorBalance = tokenP.balanceOf(_currentActor);
          if (quoteType == QuoteType.BurnExactOutput && actorBalance < testS.amountInSplit2) {
            testS.amountInSplit2 = actorBalance;
            testS.amountOutSplit2 = _parallelizerSplit.quoteIn(testS.amountInSplit2, testS.tokenIn, testS.tokenOut);
          } else if (
            quoteType == QuoteType.MintExactOutput
              && IERC20(testS.tokenIn).balanceOf(_currentActor) < testS.amountInSplit2
          ) {
            deal(testS.tokenIn, _currentActor, testS.amountInSplit2);
            IERC20(testS.tokenIn).approve(address(_parallelizerSplit), testS.amountInSplit2);
          }
        }
        _parallelizerSplit.swapExactOutput(
          testS.amountOutSplit2,
          testS.amountInSplit2,
          testS.tokenIn,
          testS.tokenOut,
          sweeper,
          block.timestamp + 1 hours
        );
      }
    }

    return (testS.amountIn, testS.amountOut);
  }
}
