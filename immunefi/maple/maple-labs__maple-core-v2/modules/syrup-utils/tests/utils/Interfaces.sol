// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { IERC20Like as IERC20LikeBase } from "../../contracts/interfaces/Interfaces.sol";

interface IBalancerVaultLike {

    enum SwapKind { GIVEN_IN, GIVEN_OUT }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address recipient;
        bool toInternalBalance;
    }

    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        address assetIn;
        address assetOut;
        uint256 amount;
        bytes userData;
    }

    function swap(
        SingleSwap calldata singleSwap,
        FundManagement calldata funds,
        uint256 limit,
        uint256 deadline
    ) external returns (uint256 assetDelta);

    function getPoolTokenInfo(
        bytes32 poolId,
        address token
    )
        external
        returns (
            uint256 cash,
            uint256 managed,
            uint256 blockNumber,
            address assetManager
        );
}

interface IERC20Like is IERC20LikeBase {

    function totalSupply() external returns (uint256 totalSupply);

}

interface IPotLike {

    function drip() external;

}

interface ISDaiLike {

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function pot() external returns (address pot);

    function previewRedeem(uint256 shares) external returns (uint256 assets);

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

}

interface IStakedSyrupLike {

    function balanceOf(address account) external view returns (uint256);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

}

interface ISyrupUserActionsLike {

    function swapToDai(uint256 syrupUsdcIn_, uint256 minDaiOut_, uint256 swapDeadline, address receiver_) external returns (uint256 daiOut_);

}

interface IPSMLike {

    function daiJoin() external returns (address daiJoin);

    function file(bytes32 what, uint256 data) external;

    function gem() external returns (address gem);

    function gemJoin() external returns (address gemJoin);

    function ilk() external returns (bytes32 ilk);

    function pocket() external returns (address pocket);

    function tout() external returns (uint256 tout);

}
