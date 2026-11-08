// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { ERC20Helper } from "../../../modules/erc20-helper/src/ERC20Helper.sol";

import { MapleProxiedInternals } from "../../../modules/maple-proxy-factory/contracts/MapleProxiedInternals.sol";

import { IMapleBasicStrategyInitializer } from "../../interfaces/basicStrategy/IMapleBasicStrategyInitializer.sol";

import {
    IERC4626Like,
    IGlobalsLike,
    IMapleProxyFactoryLike,
    IPoolLike,
    IPoolManagerLike
} from "../../interfaces/Interfaces.sol";

import { MapleBasicStrategyStorage } from "./MapleBasicStrategyStorage.sol";

contract MapleBasicStrategyInitializer is IMapleBasicStrategyInitializer, MapleBasicStrategyStorage, MapleProxiedInternals {

    fallback() external {
        ( address poolManager_, address strategyVault_ ) = abi.decode(msg.data, (address, address));

        _initialize(poolManager_, strategyVault_);
    }

    function _initialize(address poolManager_, address strategyVault_) internal {
        require(poolManager_ != address(0), "MBSI:ZERO_POOL_MANAGER");

        address globals_ = IMapleProxyFactoryLike(msg.sender).mapleGlobals();
        address pool_    = IPoolManagerLike(poolManager_).pool();
        address factory_ = IPoolManagerLike(poolManager_).factory();

        require(IGlobalsLike(globals_).isInstanceOf("POOL_MANAGER_FACTORY", factory_), "MBSI:I:INVALID_PM_FACTORY");
        require(IMapleProxyFactoryLike(factory_).isInstance(poolManager_),             "MBSI:I:INVALID_PM");

        address fundsAsset_         = IPoolLike(pool_).asset();
        address strategyVaultAsset_ = IERC4626Like(strategyVault_).asset();

        require(IGlobalsLike(globals_).isInstanceOf("STRATEGY_VAULT", strategyVault_), "MBSI:I:INVALID_STRATEGY_VAULT");
        require(fundsAsset_ == strategyVaultAsset_,                                    "MBSI:I:INVALID_STRATEGY_ASSET");
        require(ERC20Helper.approve(fundsAsset_, strategyVault_, type(uint256).max),   "MBSI:I:APPROVE_FAIL");

        locked = 1;

        fundsAsset    = fundsAsset_;
        pool          = pool_;
        poolManager   = poolManager_;
        strategyVault = strategyVault_;

        emit Initialized(pool_, poolManager_, strategyVault_);
    }

}
