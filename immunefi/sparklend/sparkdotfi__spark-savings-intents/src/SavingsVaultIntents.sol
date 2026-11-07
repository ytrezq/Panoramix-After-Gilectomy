// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { AccessControlEnumerable } from "../lib/openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";

import { IERC4626Like }         from "./interfaces/IERC4626Like.sol";
import { ISavingsVaultIntents } from "./interfaces/ISavingsVaultIntents.sol";

contract SavingsVaultIntents is ISavingsVaultIntents, AccessControlEnumerable {

    /**********************************************************************************************/
    /*** Declarations and constructor                                                           ***/
    /**********************************************************************************************/

    bytes32 public constant RELAYER = keccak256("RELAYER");

    uint256 public maxDeadlineDuration;

    mapping(address vault => VaultConfig config)   public vaultConfig;
    mapping(address vault => uint256 requestCount) public vaultRequestCount;

    mapping(address account => mapping(address vault => WithdrawRequest request)) public withdrawRequests;

    constructor(address admin, address relayer, uint256 maxDeadlineDuration_) {
        require(admin   != address(0), InvalidAdminAddress());
        require(relayer != address(0), InvalidRelayerAddress());

        require(maxDeadlineDuration_ != 0, InvalidMaxDeadlineDuration());

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(RELAYER,            relayer);

        maxDeadlineDuration = maxDeadlineDuration_;
    }

    /**********************************************************************************************/
    /*** Admin functions                                                                        ***/
    /**********************************************************************************************/

    function setMaxDeadlineDuration(uint256 maxDeadlineDuration_)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(maxDeadlineDuration_ != 0, InvalidMaxDeadlineDuration());

        maxDeadlineDuration = maxDeadlineDuration_;

        emit MaxDeadlineDurationUpdated(maxDeadlineDuration_);
    }

    function updateVaultConfig(
        address vault,
        bool    whitelisted_,
        uint256 minIntentAssets_,
        uint256 maxIntentAssets_
    )
        external onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(vault != address(0), InvalidVaultAddress());

        require(
            minIntentAssets_ < maxIntentAssets_,
            InvalidIntentAmountBounds(minIntentAssets_, maxIntentAssets_)
        );

        vaultConfig[vault] = VaultConfig({
            whitelisted     : whitelisted_,
            minIntentAssets : minIntentAssets_,
            maxIntentAssets : maxIntentAssets_
        });

        emit VaultConfigUpdated(vault, whitelisted_, minIntentAssets_, maxIntentAssets_);
    }

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function request(
        address vault,
        uint256 shares,
        address recipient,
        uint256 deadline
    )
        external returns (uint256 requestId)
    {
        VaultConfig memory vaultConfig_ = vaultConfig[vault];

        require(vaultConfig_.whitelisted, VaultNotWhitelisted());
        require(recipient != address(0),  InvalidRecipientAddress());

        uint256 assets = IERC4626Like(vault).convertToAssets(shares);

        require(
            assets >= vaultConfig_.minIntentAssets,
            IntentAssetsBelowMin(vaultConfig_.minIntentAssets, assets)
        );

        require(
            assets <= vaultConfig_.maxIntentAssets,
            IntentAssetsAboveMax(vaultConfig_.maxIntentAssets, assets)
        );

        uint256 maxDeadline = block.timestamp + maxDeadlineDuration;

        require(
            deadline > block.timestamp && deadline <= maxDeadline,
            InvalidDeadline(maxDeadline, deadline)
        );

        uint256 userShares = IERC4626Like(vault).balanceOf(msg.sender);

        require(shares <= userShares, InsufficientShares(shares, userShares));

        uint256 allowance = IERC4626Like(vault).allowance(msg.sender, address(this));

        require(shares <= allowance, InsufficientAllowance(shares, allowance));

        requestId = ++vaultRequestCount[vault];

        withdrawRequests[msg.sender][vault] = WithdrawRequest({
            requestId : requestId,
            shares    : shares,
            recipient : recipient,
            deadline  : deadline
        });

        emit RequestCreated(msg.sender, vault, requestId, shares, recipient, deadline);
    }

    function cancel(address vault) external returns (uint256 requestId) {
        requestId = withdrawRequests[msg.sender][vault].requestId;

        require(requestId != 0, RequestNotFound(msg.sender, vault));

        delete withdrawRequests[msg.sender][vault];

        emit RequestCancelled(msg.sender, vault, requestId);
    }

    function fulfill(
        address account,
        address vault,
        uint256 requestId
    )
        external
        onlyRole(RELAYER)
    {
        WithdrawRequest memory request_ = withdrawRequests[account][vault];

        require(
            requestId != 0 && request_.requestId == requestId,
            RequestNotFound(account, vault)
        );

        require(
            block.timestamp <= request_.deadline,
            DeadlineExceeded(account, vault, request_.requestId, request_.deadline)
        );

        delete withdrawRequests[account][vault];

        emit RequestFulfilled(account, vault, request_.requestId);

        IERC4626Like(vault).redeem(request_.shares, request_.recipient, account);
    }

}
