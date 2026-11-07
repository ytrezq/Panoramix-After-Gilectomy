// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

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

}

interface IERC20Like {

    function allowance(address owner, address spender) external view returns (uint256 allowance);

    function balanceOf(address account) external view returns (uint256 balance);

    function DOMAIN_SEPARATOR() external view returns (bytes32 domainSeparator);

    function PERMIT_TYPEHASH() external view returns (bytes32 permitTypehash);

    function approve(address spender, uint256 amount) external returns (bool success);

    function permit(address owner, address spender, uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    function transfer(address recipient, uint256 amount) external returns (bool success);

    function transferFrom(address owner, address recipient, uint256 amount) external returns (bool success);

}

interface IGlobalsLike {

    function governor() external view returns (address governor);

    function operationalAdmin() external view returns (address operationalAdmin);

}

interface IProxiedLike {

    function implementation() external view returns (address implementation_);

    function upgrade(uint256 toVersion_, bytes calldata arguments_) external;

}

// NOTE: Needs to be defined after `IProxiedLike`.
interface ILoanLike is IProxiedLike {

    function acceptBorrower() external;

    function acceptLender() external;

    function acceptLoanTerms() external;

    function acceptNewTerms(address refinancer_, uint256 deadline_, bytes[] calldata calls_)
        external returns (bytes32 refinanceCommitment_);

    function borrower() external view returns (address borrower_);

    function factory() external view returns (address factory_);

    function fundsAsset() external view returns (address fundsAsset_);

    function globals() external view returns (address globals_);

    function gracePeriod() external view returns (uint256 gracePeriod_);

    function isImpaired() external view returns (bool isImpaired_);

    function lender() external view returns (address lender_);

    function paymentInterval() external view returns (uint256 paymentInterval_);

    function principal() external view returns (uint256 principal_);

    function proposeNewTerms(address refinancer_, uint256 deadline_, bytes[] calldata calls_)
        external returns (bytes32 refinanceCommitment_);

    function rejectNewTerms(address refinancer_, uint256 deadline_, bytes[] calldata calls_)
        external returns (bytes32 refinanceCommitment_);

    function setPendingBorrower(address pendingBorrower_) external;

    function skim(address token_, address destination_) external returns (uint256 skimmed_);

}

interface IMigratorLike {

    function migrate(address receiver, uint256 mplAmount) external returns (uint256 syrupAmount);

}

interface IPoolLike is IERC20Like {

    function asset() external view returns (address asset);

    function convertToExitAssets(uint256 shares) external view returns (uint256);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function manager() external view returns (address manager);

}

interface IPoolManagerLike {

    function poolPermissionManager() external view returns (address poolPermissionManager);

}

interface IPoolPermissionManagerLike {

    function hasPermission(address poolManager, address lender, bytes32 functionId) external view returns (bool hasPermission);

    function permissionAdmins(address account) external view returns (bool isAdmin);

    function setLenderBitmaps(address[] calldata lenders, uint256[] calldata bitmaps) external;

}

interface IPSMLike {

    function buyGem(address account, uint256 daiAmount) external;

    function tout() external view returns (uint256 tout);  // This is the fee charged for conversion

}

interface ISDaiLike {

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

}

interface IRDTLike {

    function asset() external view returns (address asset);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

}

interface IStakedSyrupLike {

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

}
