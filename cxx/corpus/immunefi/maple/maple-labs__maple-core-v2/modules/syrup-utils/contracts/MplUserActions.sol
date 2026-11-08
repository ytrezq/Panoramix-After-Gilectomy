// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { ERC20Helper } from "../modules/erc20-helper/src/ERC20Helper.sol";

import { IMplUserActions } from "./interfaces/IMplUserActions.sol";

import { IERC20Like, IMigratorLike, IRDTLike } from "./interfaces/Interfaces.sol";

contract MplUserActions is IMplUserActions {

    /**************************************************************************************************************************************/
    /*** State Variables                                                                                                                ***/
    /**************************************************************************************************************************************/

    address public immutable override migrator;
    address public immutable override mpl;
    address public immutable override stsyrup;
    address public immutable override syrup;
    address public immutable override xmpl;

    /**************************************************************************************************************************************/
    /*** Constructor                                                                                                                    ***/
    /**************************************************************************************************************************************/

    constructor(address migrator_, address xmpl_, address stsyrup_) {
        address mpl_   = IRDTLike(xmpl_).asset();
        address syrup_ = IRDTLike(stsyrup_).asset();

        migrator = migrator_;
        mpl      = mpl_;
        syrup    = syrup_;
        xmpl     = xmpl_;
        stsyrup  = stsyrup_;

        require(ERC20Helper.approve(mpl_,   migrator_, type(uint256).max), "MUA:C:MPL_APPROVE");
        require(ERC20Helper.approve(syrup_, stsyrup_,  type(uint256).max), "MUA:C:SYRUP_APPROVE");
    }

    /**************************************************************************************************************************************/
    /*** User Actions                                                                                                                   ***/
    /**************************************************************************************************************************************/

    // MPL -> SYRUP -> stSYRUP
    function migrateAndStake(address receiver_, uint256 mplIn_) external override returns (uint256 stsyrupOut_) {
        stsyrupOut_ = _migrateAndStake(receiver_, mplIn_);
    }

    // MPL -> SYRUP -> stSYRUP
    function migrateAndStakeWithPermit(
        address receiver_,
        uint256 mplIn_,
        uint256 deadline_,
        uint8   v_,
        bytes32 r_,
        bytes32 s_
    )
        external override returns (uint256 stsyrupOut_)
    {
        _permit(mpl, deadline_, mplIn_, v_, r_, s_);

        stsyrupOut_ = _migrateAndStake(receiver_, mplIn_);
    }

    // xMPL -> MPL -> SYRUP
    function redeemAndMigrate(address receiver_, uint256 xmplIn_) external override returns (uint256 syrupOut_) {
        syrupOut_ = _redeemAndMigrate(receiver_, xmplIn_);
    }

    // xMPL -> MPL -> SYRUP
    function redeemAndMigrateWithPermit(
        address receiver_,
        uint256 xmplIn_,
        uint256 deadline_,
        uint8   v_,
        bytes32 r_,
        bytes32 s_
    )
        external override returns (uint256 syrupOut_)
    {
        _permit(xmpl, deadline_, xmplIn_, v_, r_, s_);

        syrupOut_ = _redeemAndMigrate(receiver_, xmplIn_);
    }

    // xMPL -> MPL -> SYRUP -> stSYRUP
    function redeemAndMigrateAndStake(address receiver_, uint256 xmplIn_) external override returns (uint256 stsyrupOut_) {
        stsyrupOut_ = _redeemAndMigrateAndStake(receiver_, xmplIn_);
    }

    // xMPL -> MPL -> SYRUP -> stSYRUP
    function redeemAndMigrateAndStakeWithPermit(
        address receiver_,
        uint256 xmplIn_,
        uint256 deadline_,
        uint8   v_,
        bytes32 r_,
        bytes32 s_
    )
        external override returns (uint256 stsyrupOut_)
    {
        _permit(xmpl, deadline_, xmplIn_, v_, r_, s_);

        stsyrupOut_ = _redeemAndMigrateAndStake(receiver_, xmplIn_);
    }

    /**************************************************************************************************************************************/
    /*** Internal Functions                                                                                                             ***/
    /**************************************************************************************************************************************/

    // MPL -> SYRUP -> stSYRUP
    function _migrateAndStake(address receiver_, uint256 mplIn_) internal returns (uint256 stsyrupOut_) {
        require(mplIn_ > 0,                                                       "MUA:MAS:ZERO_AMOUNT");
        require(ERC20Helper.transferFrom(mpl, msg.sender, address(this), mplIn_), "MUA:MAS:TRANSFER_FAIL");

        uint256 syrupAmount_ = _migrate(address(this), mplIn_);
        stsyrupOut_          = _stake(receiver_, syrupAmount_);

        emit MigratedAndStaked(msg.sender, mpl, mplIn_, receiver_, stsyrup, stsyrupOut_);
    }

    // MPL -> SYRUP
    function _migrate(address receiver_, uint256 mplIn_) internal returns (uint256 syrupOut_) {
        syrupOut_ = IMigratorLike(migrator).migrate(receiver_, mplIn_);
    }

    function _permit(address asset_, uint256 deadline_, uint256 amount_, uint8 v_, bytes32 r_, bytes32 s_) internal {
        uint256 allowance_ = IERC20Like(asset_).allowance(msg.sender, address(this));

        if (allowance_ < amount_) {
            IERC20Like(asset_).permit(msg.sender, address(this), amount_, deadline_, v_, r_, s_);
        }
    }

    // xMPL -> MPL
    function _redeem(address receiver_, uint256 xmplIn_) internal returns (uint256 mplOut_) {
        mplOut_ = IRDTLike(xmpl).redeem(xmplIn_, receiver_, address(this));
    }

    // xMPL -> MPL -> SYRUP
    function _redeemAndMigrate(address receiver_, uint256 xmplIn_) internal returns (uint256 syrupOut_) {
        require(xmplIn_ > 0,                                                        "MUA:RAM:ZERO_AMOUNT");
        require(ERC20Helper.transferFrom(xmpl, msg.sender, address(this), xmplIn_), "MUA:RAM:TRANSFER_FAIL");

        uint256 mplAmount_ = _redeem(address(this), xmplIn_);
        syrupOut_          = _migrate(receiver_, mplAmount_);

        emit RedeemedAndMigrated(msg.sender, xmpl, xmplIn_, receiver_, syrup, syrupOut_);
    }

    // xMPL -> MPL -> SYRUP -> stSYRUP
    function _redeemAndMigrateAndStake(address receiver_, uint256 xmplIn_) internal returns (uint256 stsyrupOut_) {
        require(xmplIn_ > 0,                                                        "MUA:RAMAS:ZERO_AMOUNT");
        require(ERC20Helper.transferFrom(xmpl, msg.sender, address(this), xmplIn_), "MUA:RAMAS:TRANSFER_FAIL");

        uint256 mplAmount_   = _redeem(address(this), xmplIn_);
        uint256 syrupAmount_ = _migrate(address(this), mplAmount_);
        stsyrupOut_          = _stake(receiver_, syrupAmount_);

        emit RedeemedAndMigratedAndStaked(msg.sender, xmpl, xmplIn_, receiver_, stsyrup, stsyrupOut_);
    }

    // SYRUP -> stSYRUP
    function _stake(address receiver_, uint256 syrupIn_) internal returns (uint256 stsyrupOut_) {
        stsyrupOut_ = IRDTLike(stsyrup).deposit(syrupIn_, receiver_);
    }

}
