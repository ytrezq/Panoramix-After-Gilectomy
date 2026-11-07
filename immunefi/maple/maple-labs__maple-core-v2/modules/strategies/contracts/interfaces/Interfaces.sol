// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IAavePoolLike {

    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    function withdraw(address asset, uint256 amount, address to) external returns (uint256);

}

interface IAaveRewardsControllerLike {

    function claimRewards(
        address[] calldata assets,
        uint256 amount,
        address to,
        address rewardToken
    ) external returns (uint256 rewardAmount);

}

interface IAaveTokenLike {

    function balanceOf(address account_) external view returns (uint256 balance_);

    function getIncentivesController() external view returns (address incentivesController);

    function POOL() external view returns (address pool);

    function UNDERLYING_ASSET_ADDRESS() external view returns (address asset);

}

interface IERC20Like {

    function approve(address spender, uint256 amount) external returns (bool success);

    function balanceOf(address account_) external view returns (uint256 balance_);

    function transfer(address to, uint256 amount) external returns (bool);

}

interface IERC4626Like {

    function asset() external view returns (address asset_);

    function balanceOf(address account_) external view returns (uint256 balance_);

    function convertToAssets(uint256 shares_) external view returns (uint256 assets_);

    function convertToShares(uint256 assets_) external view returns (uint256 shares_);

    function deposit(uint256 assets_, address receiver_) external returns (uint256 shares_);

    function maxWithdraw(address owner_) external view returns (uint256 maxAssets_);

    function previewRedeem(uint256 shares) external view returns (uint256 assets_);

    function redeem(uint256 shares_, address receiver_, address owner_) external returns (uint256 assets_);

    function withdraw(uint256 assets_, address receiver_, address owner_) external returns (uint256 shares_);
}

interface IGlobalsLike {

    function canDeploy(address caller_) external view returns (bool canDeploy_);

    function isFunctionPaused(bytes4 sig_) external view returns (bool isFunctionPaused_);

    function governor() external view returns (address governor_);

    function isInstanceOf(bytes32 instanceId, address instance_) external view returns (bool isInstance_);

    function isValidScheduledCall(
        address caller_,
        address contract_,
        bytes32 functionId_,
        bytes calldata callData_
    ) external view returns (bool isValid_);

    function mapleTreasury() external view returns (address mapleTreasury_);

    function operationalAdmin() external view returns (address operationalAdmin_);

    function securityAdmin() external view returns (address securityAdmin_);

    function unscheduleCall(address caller_, bytes32 functionId_, bytes calldata callData_) external;

}

interface IMapleProxyFactoryLike {

    function isInstance(address instance_) external view returns (bool isInstance_);

    function mapleGlobals() external view returns (address globals_);

}

interface IPoolLike {

    function asset() external view returns (address asset_);

    function manager() external view returns (address poolManager_);

}

interface IPoolManagerLike {

    function factory() external view returns (address factory_);

    function pool() external view returns (address pool_);

    function poolDelegate() external view returns (address poolDelegate_);

    function requestFunds(address destination_, uint256 principal_) external;

}

interface IPSMLike {

    function buyGem(address usr, uint256 gemAmt) external returns (uint256 daiInWad);

    function gem() external view returns (address gem_);

    function sellGem(address usr, uint256 gemAmt) external returns (uint256 daiOutWad);

    function tin() external view returns (uint256 tin); // Sell side fee

    function tout() external view returns (uint256 tout); // Buy side fee

    function to18ConversionFactor() external view returns (uint256 to18ConversionFactor);

    function usds() external view returns (address usds_);

}
