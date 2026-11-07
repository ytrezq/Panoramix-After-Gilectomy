// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { ERC20Helper } from "../modules/erc20-helper/src/ERC20Helper.sol";

import { StrategyState }     from "./interfaces/IMapleStrategy.sol";
import { IMapleSkyStrategy } from "./interfaces/skyStrategy/IMapleSkyStrategy.sol";

import {
    IERC20Like,
    IERC4626Like,
    IGlobalsLike,
    IMapleProxyFactoryLike,
    IPoolLike,
    IPoolManagerLike,
    IPSMLike
} from "./interfaces/Interfaces.sol";

import { MapleSkyStrategyStorage } from "./proxy/skyStrategy/MapleSkyStrategyStorage.sol";

import { MapleAbstractStrategy } from "./MapleAbstractStrategy.sol";

/*
███╗   ███╗ █████╗ ██████╗ ██╗     ███████╗
████╗ ████║██╔══██╗██╔══██╗██║     ██╔════╝
██╔████╔██║███████║██████╔╝██║     █████╗
██║╚██╔╝██║██╔══██║██╔═══╝ ██║     ██╔══╝
██║ ╚═╝ ██║██║  ██║██║     ███████╗███████╗
╚═╝     ╚═╝╚═╝  ╚═╝╚═╝     ╚══════╝╚══════╝

███████╗██╗  ██╗██╗   ██╗
██╔════╝██║ ██╔╝╚██╗ ██╔╝
███████╗█████╔╝  ╚████╔╝
╚════██║██╔═██╗   ╚██╔╝
███████║██║  ██╗   ██║
╚══════╝╚═╝  ╚═╝   ╚═╝

███████╗████████╗██████╗  █████╗ ████████╗███████╗ ██████╗██╗   ██╗
██╔════╝╚══██╔══╝██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██╔════╝╚██╗ ██╔╝
███████╗   ██║   ██████╔╝███████║   ██║   █████╗  ██║  ███╗╚████╔╝
╚════██║   ██║   ██╔══██╗██╔══██║   ██║   ██╔══╝  ██║   ██║ ╚██╔╝
███████║   ██║   ██║  ██║██║  ██║   ██║   ███████╗╚██████╔╝  ██║
╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚══════╝ ╚═════╝   ╚═╝
*/

contract MapleSkyStrategy is IMapleSkyStrategy, MapleSkyStrategyStorage, MapleAbstractStrategy {

    string public constant override STRATEGY_TYPE = "SKY";

    uint256 internal constant WAD = 1e18;

    uint256 public constant HUNDRED_PERCENT = 1e6;  // 100.0000%

    /**************************************************************************************************************************************/
    /*** Strategy Manager Functions                                                                                                     ***/
    /**************************************************************************************************************************************/

    function fundStrategy(uint256 assetsIn_) external override nonReentrant whenProtocolNotPaused onlyStrategyManager onlyActive {
        address globals_     = globals();
        address psm_         = psm;
        address savingsUsds_ = savingsUsds;

        require(IGlobalsLike(globals_).isInstanceOf("STRATEGY_VAULT", savingsUsds_), "MSS:FS:INVALID_STRATEGY_VAULT");
        require(IGlobalsLike(globals_).isInstanceOf("PSM", psm_),                    "MSS:FS:INVALID_PSM");

        _accrueFees(psm_, savingsUsds_);

        IPoolManagerLike(poolManager).requestFunds(address(this), assetsIn_);

        // NOTE: Assume Gem asset and USDS are interchangeable 1:1 for the purposes of Pool Accounting
        uint256 usdsOut_ = IPSMLike(psm_).sellGem(address(this), assetsIn_);

        uint256 shares_ = IERC4626Like(savingsUsds_).deposit(usdsOut_, address(this));

        lastRecordedTotalAssets = _currentTotalAssets(psm_, savingsUsds_);

        emit StrategyFunded(assetsIn_, shares_);
    }

    function withdrawFromStrategy(uint256 assetsOut_) external override nonReentrant whenProtocolNotPaused onlyStrategyManager {
        require(assetsOut_ > 0, "MSS:WFS:ZERO_ASSETS");

        address psm_         = psm;
        address savingsUsds_ = savingsUsds;

        bool isStrategyActive_ = _strategyState() == StrategyState.Active;

        if (isStrategyActive_) {
            require(assetsOut_ <= assetsUnderManagement(), "MSS:WFS:LOW_ASSETS");

            _accrueFees(psm_, savingsUsds_);
        }

        uint256 shares_ = _withdraw(psm_, savingsUsds_, assetsOut_, pool);

        if (isStrategyActive_) {
            lastRecordedTotalAssets = _currentTotalAssets(psm_, savingsUsds_);
        }

        emit StrategyWithdrawal(assetsOut_, shares_);
    }

    /**************************************************************************************************************************************/
    /*** Strategy Admin Functions                                                                                                       ***/
    /**************************************************************************************************************************************/

    function deactivateStrategy() external override nonReentrant whenProtocolNotPaused onlyProtocolAdmins {
        require(_strategyState() != StrategyState.Inactive, "MSS:DS:ALREADY_INACTIVE");

        strategyState = StrategyState.Inactive;

        emit StrategyDeactivated();
    }

    function impairStrategy() external override nonReentrant whenProtocolNotPaused onlyProtocolAdmins {
        require(_strategyState() != StrategyState.Impaired, "MSS:IS:ALREADY_IMPAIRED");

        strategyState = StrategyState.Impaired;

        emit StrategyImpaired();
    }

    function reactivateStrategy(bool updateAccounting_) external override nonReentrant whenProtocolNotPaused onlyProtocolAdmins {
        require(_strategyState() != StrategyState.Active, "MSS:RS:ALREADY_ACTIVE");

        // Updating the fee accounting will result in no fees being charged for the period of impairment and/or inactivity.
        // Otherwise, fees will be charged retroactively as if no impairment and/or deactivation occurred.
        if (updateAccounting_) {
            lastRecordedTotalAssets = _currentTotalAssets(psm, savingsUsds);
        }

        strategyState = StrategyState.Active;

        emit StrategyReactivated(updateAccounting_);
    }

    function setPsm(address newPsm_) external override nonReentrant whenProtocolNotPaused onlyProtocolAdmins {
        require(newPsm_ != address(0), "MSS:SPSM:ZERO_ADDRESS");

        address fundsAsset_ = fundsAsset;
        address oldPsm_     = psm;
        address usds_       = usds;

        require(IPSMLike(newPsm_).gem() == fundsAsset_, "MSS:SPSM:INVALID_GEM");
        require(IPSMLike(newPsm_).usds() == usds_,      "MSS:SPSM:INVALID_USDS");

        require(IGlobalsLike(globals()).isInstanceOf("PSM", newPsm_), "MSS:SPSM:INVALID_PSM");

        require(ERC20Helper.approve(fundsAsset_, oldPsm_, 0),                 "MSS:SPSM:GEM_APPROVE_FAIL");
        require(ERC20Helper.approve(fundsAsset_, newPsm_, type(uint256).max), "MSS:SPSM:GEM_APPROVE_FAIL");
        require(ERC20Helper.approve(usds_,       oldPsm_, 0),                 "MSS:SPSM:USDS_APPROVE_FAIL");
        require(ERC20Helper.approve(usds_,       newPsm_, type(uint256).max), "MSS:SPSM:USDS_APPROVE_FAIL");

        emit PsmSet(psm = newPsm_);
    }

    function setStrategyFeeRate(uint256 strategyFeeRate_)
        external override nonReentrant whenProtocolNotPaused onlyProtocolAdmins onlyActive
    {
        require(strategyFeeRate_ <= HUNDRED_PERCENT, "MSS:SSFR:INVALID_FEE_RATE");

        address psm_         = psm;
        address savingsUsds_ = savingsUsds;

        // Account for any fees before changing the fee rate
        _accrueFees(psm_, savingsUsds_);

        lastRecordedTotalAssets = _currentTotalAssets(psm_, savingsUsds_);
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

        uint256 currentTotalAssets_ = _currentTotalAssets(psm, savingsUsds);

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

    function _accrueFees(address psm_, address savingsUsds_) internal {
        uint256 currentTotalAssets_ = _currentTotalAssets(psm_, savingsUsds_);
        uint256 strategyFee_        = _currentAccruedFees(currentTotalAssets_);

        // Withdraw the fees from the strategy vault.
        if (strategyFee_ != 0) {
            _withdraw(psm_, savingsUsds_, strategyFee_, treasury());

            emit StrategyFeesCollected(strategyFee_);
        }
    }

    function _setLock(uint256 lock_) internal override {
        locked = lock_;
    }

    function _withdraw(address psm_, address savingsUsds_, uint256 assets_, address destination_) internal returns (uint256 shares_) {
        uint256 requiredUsds_ = _usdsForGem(psm_, assets_);

        shares_ = IERC4626Like(savingsUsds_).withdraw(requiredUsds_, address(this), address(this));

        // There might be some USDS left over in this contract due to rounding.
        IPSMLike(psm_).buyGem(destination_, assets_);
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

    function _currentTotalAssets(address psm_, address savingsUsds_) internal view returns (uint256 currentTotalAssets_) {
        currentTotalAssets_ =
            _gemForUsds(psm_, IERC4626Like(savingsUsds_).previewRedeem(IERC20Like(savingsUsds_).balanceOf(address(this))));
    }

    function _gemForUsds(address psm_, uint256 usdsAmount_) internal view returns (uint256 gemAmount_) {
        uint256 tout_                 = IPSMLike(psm_).tout();
        uint256 to18ConversionFactor_ = IPSMLike(psm_).to18ConversionFactor();

        // Inverse of `_usdsForGem(psm_, gemAmount_)`
        gemAmount_ = (usdsAmount_ * WAD) / (to18ConversionFactor_ * (WAD + tout_));
    }

    function _locked() internal view override returns (uint256) {
        return locked;
    }

    function _strategyState() internal view override returns (StrategyState) {
        return strategyState;
    }

    function _usdsForGem(address psm_, uint256 gemAmount_) internal view returns (uint256 usdsAmount_) {
        uint256 tout_                 = IPSMLike(psm_).tout();
        uint256 to18ConversionFactor_ = IPSMLike(psm_).to18ConversionFactor();
        uint256 gemAmt18_             = gemAmount_ * to18ConversionFactor_;

        // Inverse of `_gemForUsds(psm_, usdsAmount_)`
        usdsAmount_ = gemAmt18_ + gemAmt18_ * tout_ / WAD;
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
