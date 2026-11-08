// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

interface IPLimitOrderType {
    enum OrderType {
        SY_FOR_PT,
        PT_FOR_SY,
        SY_FOR_YT,
        YT_FOR_SY
    }
}

struct Order {
    uint256 salt;
    uint256 expiry;
    uint256 nonce;
    IPLimitOrderType.OrderType orderType;
    address token;
    address YT;
    address maker;
    address receiver;
    uint256 makingAmount;
    uint256 lnImpliedRate;
    uint256 failSafeRate;
    bytes permit;
}

struct FillOrderParams {
    Order order;
    bytes signature;
    uint256 makingAmount;
}

struct LimitOrderData {
    address limitRouter;
    uint256 epsSkipMarket; // only used for swap operations, will be ignored otherwise
    FillOrderParams[] normalFills;
    FillOrderParams[] flashFills;
    bytes optData;
}

struct ApproxParams {
    uint256 guessMin;
    uint256 guessMax;
    uint256 guessOffchain; // pass 0 in to skip this variable
    uint256 maxIteration; // every iteration, the diff between guessMin and guessMax will be divided by 2
    uint256 eps; // the max eps between the returned result & the correct result, base 1e18. Normally this number will be set
    // to 1e15 (1e18/1000 = 0.1%)
}