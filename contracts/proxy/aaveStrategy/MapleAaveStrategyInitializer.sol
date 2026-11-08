// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { ERC20Helper } from "../../../modules/erc20-helper/src/ERC20Helper.sol";

import { IMapleAaveStrategyInitializer } from "../../interfaces/aaveStrategy/IMapleAaveStrategyInitializer.sol";

import {
    IAaveTokenLike,
    IGlobalsLike,
    IMapleProxyFactoryLike,
    IPoolLike,
    IPoolManagerLike
} from "../../interfaces/Interfaces.sol";

import { MapleAaveStrategyStorage } from "./MapleAaveStrategyStorage.sol";

contract MapleAaveStrategyInitializer is IMapleAaveStrategyInitializer, MapleAaveStrategyStorage {

    fallback() external {
        ( address poolManager_, address aaveToken_ ) = abi.decode(msg.data, (address, address));

        _initialize(poolManager_, aaveToken_);
    }

    function _initialize(address poolManager_, address aaveToken_) internal {
        require(poolManager_ != address(0), "MASI:I:ZERO_POOL_MANAGER");
        require(aaveToken_   != address(0), "MASI:I:ZERO_AAVE_TOKEN");

        address globals_     = IMapleProxyFactoryLike(msg.sender).mapleGlobals();
        address pool_        = IPoolManagerLike(poolManager_).pool();
        address factory_     = IPoolManagerLike(poolManager_).factory();
        address aavePool_    = IAaveTokenLike(aaveToken_).POOL();
        address fundsAsset_  = IAaveTokenLike(aaveToken_).UNDERLYING_ASSET_ADDRESS();

        require(IGlobalsLike(globals_).isInstanceOf("POOL_MANAGER_FACTORY", factory_), "MASI:I:INVALID_PM_FACTORY");
        require(IMapleProxyFactoryLike(factory_).isInstance(poolManager_),             "MASI:I:INVALID_PM");
        require(IGlobalsLike(globals_).isInstanceOf("STRATEGY_VAULT", aaveToken_),     "MASI:I:INVALID_STRATEGY");
        require(IPoolLike(pool_).asset() == fundsAsset_,                               "MASI:I:INVALID_ASSET");
        require(ERC20Helper.approve(fundsAsset_, aavePool_, type(uint256).max),        "MASI:I:APPROVE_FAIL");

        aavePool    = aavePool_;
        aaveToken   = aaveToken_;
        pool        = pool_;
        fundsAsset  = fundsAsset_;
        poolManager = poolManager_;

        locked = 1;

        emit Initialized(aavePool_, aaveToken_, pool_, fundsAsset_, poolManager_);
    }

}
