// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { ERC20Helper } from "../modules/erc20-helper/src/ERC20Helper.sol";

import { ISyrupUserActions } from "./interfaces/ISyrupUserActions.sol";

import { IBalancerVaultLike, IERC20Like, IPSMLike, ISDaiLike } from "./interfaces/Interfaces.sol";

contract SyrupUserActions is ISyrupUserActions {

    address public constant override BAL_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant override USDC      = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint256 public constant override PSM_PRECISION = 1e12;  // The PSM expected 1e18 minus the decimals of the gem (eg. 18 - 6 = 12)

    address public immutable override dai;
    address public immutable override psm;
    address public immutable override sDai;
    address public immutable override syrupUsdc;

    bytes32 public immutable override poolId;

    uint256 internal _locked;

    constructor(address dai_, address psm_, address sDai_, address syrupUsdc_, bytes32 poolId_) {
        dai       = dai_;
        psm       = psm_;
        sDai      = sDai_;
        syrupUsdc = syrupUsdc_;
        poolId    = poolId_;

        _locked = 1;

        require(ERC20Helper.approve(syrupUsdc, BAL_VAULT, type(uint256).max), "SUA:C:SYRUP_APPROVE_FAIL");
        require(ERC20Helper.approve(dai,       psm,       type(uint256).max), "SUA:C:DAI_APPROVE_FAIL");
    }

    modifier nonReentrant() {
        require(_locked == 1, "SUA:LOCKED");

        _locked = 2;

        _;

        _locked = 1;
    }

    /**************************************************************************************************************************************/
    /*** User Actions                                                                                                                   ***/
    /**************************************************************************************************************************************/

    function swapToDai(
        uint256 syrupUsdcIn_,
        uint256 minDaiOut_,
        uint256 swapDeadline_,
        address receiver_
    )
        external override nonReentrant returns (uint256 daiOut_)
    {
        daiOut_ = _swap(syrupUsdcIn_, minDaiOut_, swapDeadline_, dai, receiver_);
    }

    function swapToDaiWithPermit(
        uint256 syrupUsdcIn_,
        uint256 minDaiOut_,
        uint256 swapDeadline_,
        address receiver_,
        uint256 permitDeadline_,
        uint8   v_,
        bytes32 r_,
        bytes32 s_
    )
        external override nonReentrant returns (uint256 daiOut_)
    {
        _permit(syrupUsdc, permitDeadline_, syrupUsdcIn_, v_, r_, s_);

        daiOut_ = _swap(syrupUsdcIn_, minDaiOut_, swapDeadline_, dai, receiver_);
    }

    function swapToUsdc(
        uint256 syrupUsdcIn_,
        uint256 minUsdcOut_,
        uint256 swapDeadline_,
        address receiver_
    )
        external override nonReentrant returns (uint256 usdcOut_)
    {
       usdcOut_ = _swap(syrupUsdcIn_, minUsdcOut_, swapDeadline_, USDC, receiver_);
    }

     function swapToUsdcWithPermit(
        uint256 syrupUsdcIn_,
        uint256 minUsdcOut_,
        uint256 swapDeadline_,
        address receiver_,
        uint256 permitDeadline_,
        uint8   v_,
        bytes32 r_,
        bytes32 s_
    )
        external override nonReentrant returns (uint256 usdcOut_)
    {
        _permit(syrupUsdc, permitDeadline_, syrupUsdcIn_, v_, r_, s_);

        usdcOut_ = _swap(syrupUsdcIn_, minUsdcOut_, swapDeadline_, USDC, receiver_);
    }

    /**************************************************************************************************************************************/
    /*** Internal Swap Function                                                                                                         ***/
    /**************************************************************************************************************************************/

    function _swap(
        uint256 syrupUsdcIn_,
        uint256 minAmountOut_,
        uint256 swapDeadline_,
        address assetOut_,
        address receiver_
    )
        internal returns (uint256 amountOut_)
    {
        // 1. Pull SyrupUSDC from the user
        require(ERC20Helper.transferFrom(syrupUsdc, msg.sender, address(this), syrupUsdcIn_), "SUA:S:TRANSFER_FROM_FAILED");

        // 2. Swap into sDAI
        uint256 sdaiAmount_ = _swapViaBalancer(syrupUsdcIn_, swapDeadline_);

        // 3. Swap into DAI
        amountOut_ = _redeemForDai(sdaiAmount_, assetOut_ == USDC ? address(this) : receiver_);

        // 4. If asset out is USDC, swap DAI to USDC
        if (assetOut_ == USDC) {
            amountOut_ = _swapDaiForUsdc(amountOut_, receiver_);
        }

        require(amountOut_ >= minAmountOut_, "SUA:S:INSUFFICIENT_AMOUNT_OUT");

        emit Swap(msg.sender, receiver_, syrupUsdc, syrupUsdcIn_, assetOut_, amountOut_);
    }

    /**************************************************************************************************************************************/
    /*** Internal Functions                                                                                                             ***/
    /**************************************************************************************************************************************/

    function _permit(address asset_, uint256 deadline_, uint256 amount_, uint8 v_, bytes32 r_, bytes32 s_) internal {
        uint256 allowance_ = IERC20Like(asset_).allowance(msg.sender, address(this));

        if (allowance_ < amount_) {
            IERC20Like(asset_).permit(msg.sender, address(this), amount_, deadline_, v_, r_, s_);
        }
    }

    function _redeemForDai(uint256 sdaiIn_, address receiver_) internal returns (uint256 daiOut_) {
        daiOut_ = ISDaiLike(sDai).redeem(sdaiIn_, receiver_, address(this));
    }

    function _swapDaiForUsdc(uint256 daiIn_, address receiver_) internal returns (uint256 usdcOut_) {
        IPSMLike psm_ = IPSMLike(psm);
        // Calculate the exact amount of gems we expect to receive given this amount of assets
        // We are reversing the calculation at
        // https://github.com/makerdao/dss-psm/blob/222c96d4047e76680ed6803f07dd61aa2590e42b/src/psm.sol#L121
        // Note: Due to rounding, this may leave dai dust in the contract
        usdcOut_ = daiIn_ * 1e18 / (PSM_PRECISION * (1e18 + psm_.tout()));
        psm_.buyGem(receiver_, usdcOut_);
    }

    function _swapViaBalancer(uint256 syrupUsdcIn_, uint256 swapDeadline_) internal returns (uint256 sdaiOut_) {
        IBalancerVaultLike.FundManagement memory funds_ = IBalancerVaultLike.FundManagement({
            sender:              address(this),
            fromInternalBalance: false,
            recipient:           address(this),
            toInternalBalance:   false
        });

        IBalancerVaultLike.SingleSwap memory swap_ = IBalancerVaultLike.SingleSwap({
            poolId:   poolId,
            kind:     IBalancerVaultLike.SwapKind.GIVEN_IN,
            assetIn:  syrupUsdc,
            assetOut: sDai,
            amount:   syrupUsdcIn_,
            userData: new bytes(0)
        });

        sdaiOut_ = IBalancerVaultLike(BAL_VAULT).swap({
            singleSwap: swap_,
            funds:      funds_,
            limit:      0,
            deadline:   swapDeadline_
        });
    }

}
