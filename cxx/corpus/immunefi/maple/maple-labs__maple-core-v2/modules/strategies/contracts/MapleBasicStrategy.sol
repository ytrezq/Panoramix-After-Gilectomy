// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { StrategyState }       from "./interfaces/IMapleStrategy.sol";
import { IMapleBasicStrategy } from "./interfaces/basicStrategy/IMapleBasicStrategy.sol";

import {
    IERC20Like,
    IERC4626Like,
    IGlobalsLike,
    IMapleProxyFactoryLike,
    IPoolLike,
    IPoolManagerLike
} from "./interfaces/Interfaces.sol";

import { MapleBasicStrategyStorage } from "./proxy/basicStrategy/MapleBasicStrategyStorage.sol";

import { MapleAbstractStrategy } from "./MapleAbstractStrategy.sol";

/*
███╗   ███╗ █████╗ ██████╗ ██╗     ███████╗
████╗ ████║██╔══██╗██╔══██╗██║     ██╔════╝
██╔████╔██║███████║██████╔╝██║     █████╗
██║╚██╔╝██║██╔══██║██╔═══╝ ██║     ██╔══╝
██║ ╚═╝ ██║██║  ██║██║     ███████╗███████╗
╚═╝     ╚═╝╚═╝  ╚═╝╚═╝     ╚══════╝╚══════╝

██████╗  █████╗ ███████╗██╗ ██████╗
██╔══██╗██╔══██╗██╔════╝██║██╔════╝
██████╔╝███████║███████╗██║██║
██╔══██╗██╔══██║╚════██║██║██║
██████╔╝██║  ██║███████║██║╚██████╗
╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝ ╚═════╝

███████╗████████╗██████╗  █████╗ ████████╗███████╗ ██████╗██╗   ██╗
██╔════╝╚══██╔══╝██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██╔════╝╚██╗ ██╔╝
███████╗   ██║   ██████╔╝███████║   ██║   █████╗  ██║  ███╗╚████╔╝
╚════██║   ██║   ██╔══██╗██╔══██║   ██║   ██╔══╝  ██║   ██║ ╚██╔╝
███████║   ██║   ██║  ██║██║  ██║   ██║   ███████╗╚██████╔╝  ██║
╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚══════╝ ╚═════╝   ╚═╝
*/

contract MapleBasicStrategy is IMapleBasicStrategy, MapleBasicStrategyStorage, MapleAbstractStrategy {

    string public constant override STRATEGY_TYPE = "BASIC";

    uint256 public constant HUNDRED_PERCENT = 1e6;  // 100.0000%

    /**************************************************************************************************************************************/
    /*** Strategy Manager Functions                                                                                                     ***/
    /**************************************************************************************************************************************/

    function fundStrategy(uint256 assetsIn_, uint256 minSharesOut_) external override nonReentrant whenProtocolNotPaused onlyStrategyManager onlyActive {
        address strategyVault_ = strategyVault;

        require(IGlobalsLike(globals()).isInstanceOf("STRATEGY_VAULT", strategyVault_), "MBS:FS:INVALID_VAULT");

        _accrueFees(strategyVault_);

        IPoolManagerLike(poolManager).requestFunds(address(this), assetsIn_);

        uint256 shares_ = IERC4626Like(strategyVault_).deposit(assetsIn_, address(this));

        require(shares_ >= minSharesOut_, "MBS:FS:MIN_SHARES");

        lastRecordedTotalAssets = _currentTotalAssets(strategyVault_);

        emit StrategyFunded(assetsIn_, shares_);
    }

    function withdrawFromStrategy(uint256 assetsOut_, uint256 maxSharesBurned_)
        external override nonReentrant whenProtocolNotPaused onlyStrategyManager
    {
        require(assetsOut_ > 0, "MBS:WFS:ZERO_ASSETS");

        address strategyVault_ = strategyVault;
        bool isStrategyActive_ = _strategyState() == StrategyState.Active;

        // Strategy only accrues fees when it is active.
        if (isStrategyActive_) {
            require(assetsOut_ <= assetsUnderManagement(), "MBS:WFS:LOW_ASSETS");

            _accrueFees(strategyVault_);
        }

        uint256 shares_ = IERC4626Like(strategyVault_).withdraw(assetsOut_, address(pool), address(this));

        require(shares_ <= maxSharesBurned_, "MBS:WFS:SLIPPAGE");

        if (isStrategyActive_) {
            lastRecordedTotalAssets = _currentTotalAssets(strategyVault_);
        }

        emit StrategyWithdrawal(assetsOut_, shares_);
    }

    /**************************************************************************************************************************************/
    /*** Strategy Admin Functions                                                                                                       ***/
    /**************************************************************************************************************************************/

    function deactivateStrategy() external override nonReentrant whenProtocolNotPaused onlyProtocolAdmins {
        require(_strategyState() != StrategyState.Inactive, "MBS:DS:ALREADY_INACTIVE");

        strategyState = StrategyState.Inactive;

        emit StrategyDeactivated();
    }

    function impairStrategy() external override nonReentrant whenProtocolNotPaused onlyProtocolAdmins {
        require(_strategyState() != StrategyState.Impaired, "MBS:IS:ALREADY_IMPAIRED");

        strategyState = StrategyState.Impaired;

        emit StrategyImpaired();
    }

    function reactivateStrategy(bool updateAccounting_) external override nonReentrant whenProtocolNotPaused onlyProtocolAdmins {
        require(_strategyState() != StrategyState.Active, "MBS:RS:ALREADY_ACTIVE");

        // Updating the fee accounting will result in no fees being charged for the period of impairment and/or inactivity.
        // Otherwise, fees will be charged retroactively as if no impairment and/or deactivation occurred.
        if (updateAccounting_) {
            lastRecordedTotalAssets = _currentTotalAssets(strategyVault);
        }

        strategyState = StrategyState.Active;

        emit StrategyReactivated(updateAccounting_);
    }

    function setStrategyFeeRate(uint256 strategyFeeRate_)
        external override nonReentrant whenProtocolNotPaused onlyProtocolAdmins onlyActive
    {
        address strategyVault_ = strategyVault;

        require(strategyFeeRate_ <= HUNDRED_PERCENT, "MBS:SSFR:INVALID_FEE_RATE");

        _accrueFees(strategyVault_);

        lastRecordedTotalAssets = _currentTotalAssets(strategyVault_);
        strategyFeeRate         = strategyFeeRate_;

        emit StrategyFeeRateSet(strategyFeeRate_);
    }

    /**************************************************************************************************************************************/
    /*** Strategy View Functions                                                                                                        ***/
    /**************************************************************************************************************************************/

    function assetsUnderManagement() public view override returns (uint256 assetsUnderManagement_) {
        // All assets are marked as zero if the strategy is inactive.
        if (_strategyState() == StrategyState.Inactive) {
            return 0;
        }

        uint256 currentTotalAssets_ = _currentTotalAssets(strategyVault);

        assetsUnderManagement_ = currentTotalAssets_ - _currentAccruedFees(currentTotalAssets_);
    }

    function unrealizedLosses() external view override returns (uint256 unrealizedLosses_) {
        if (_strategyState() == StrategyState.Impaired) {
            unrealizedLosses_ = assetsUnderManagement();
        }
    }

    /**************************************************************************************************************************************/
    /*** Internal Helpers                                                                                                               ***/
    /**************************************************************************************************************************************/

    function _accrueFees(address strategyVault_) internal {
        uint256 currentTotalAssets_ = _currentTotalAssets(strategyVault_);
        uint256 strategyFee_        = _currentAccruedFees(currentTotalAssets_);

        // Withdraw the fees from the strategy vault.
        if (strategyFee_ != 0) {
            IERC4626Like(strategyVault_).withdraw(strategyFee_, treasury(), address(this));

            emit StrategyFeesCollected(strategyFee_);
        }
    }

    function _setLock(uint256 lock_) internal override {
        locked = lock_;
    }

    /**************************************************************************************************************************************/
    /*** Internal View Functions                                                                                                        ***/
    /**************************************************************************************************************************************/

    function _currentAccruedFees(uint256 currentTotalAssets_) internal view returns (uint256 currentAccruedFees_) {
        uint256 lastRecordedTotalAssets_ = lastRecordedTotalAssets;
        uint256 strategyFeeRate_         = strategyFeeRate;

        // No fees to accrue if TotalAssets has decreased or fee rate is zero.
        if (currentTotalAssets_ <= lastRecordedTotalAssets_ || strategyFeeRate_ == 0) {
            return 0;
        }

        // Can't underflow due to check above.
        uint256 yieldAccrued_ = currentTotalAssets_ - lastRecordedTotalAssets_;

        // It is acknowledged that `currentAccruedFees_` may be rounded down to 0 if `yieldAccrued_ * strategyFeeRate_ < HUNDRED_PERCENT`.
        currentAccruedFees_ = yieldAccrued_ * strategyFeeRate_ / HUNDRED_PERCENT;
    }

    function _currentTotalAssets(address strategyVault_) internal view returns (uint256 currentTotalAssets_) {
        uint256 currentTotalShares_ = IERC20Like(strategyVault_).balanceOf(address(this));

        currentTotalAssets_ = IERC4626Like(strategyVault_).previewRedeem(currentTotalShares_);
    }

    function _locked() internal view override returns (uint256) {
        return locked;
    }

    function _strategyState() internal view override returns (StrategyState) {
        return strategyState;
    }

    /**************************************************************************************************************************************/
    /*** View Functions                                                                                                                 ***/
    /**************************************************************************************************************************************/

    function factory() external view override returns (address factory_) {
        factory_ = _factory();
    }

    function globals() public view override returns (address globals_) {
        globals_ = IMapleProxyFactoryLike(_factory()).mapleGlobals();
    }

    function governor() public view override returns (address governor_) {
        governor_ = IGlobalsLike(globals()).governor();
    }

    function implementation() external view override returns (address implementation_) {
        implementation_ = _implementation();
    }

    function poolDelegate() public view override returns (address poolDelegate_) {
        poolDelegate_ = IPoolManagerLike(poolManager).poolDelegate();
    }

    function securityAdmin() public view override returns (address securityAdmin_) {
        securityAdmin_ = IGlobalsLike(globals()).securityAdmin();
    }

    function treasury() public view override returns (address treasury_) {
        treasury_ = IGlobalsLike(globals()).mapleTreasury();
    }

}
