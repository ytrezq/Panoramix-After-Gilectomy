// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ConcreteV2ConversionLib as ConversionLib} from "../lib/Conversion.sol";
import {Math} from "@openzeppelin-contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20_OZ_5_2_0_Lib} from "../lib/ERC20Lib.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ConcreteAsyncVaultImplStorageLib} from "../lib/storage/ConcreteAsyncVaultImplStorageLib.sol";
import {IConcreteAsyncVaultImpl} from "../interface/IConcreteAsyncVaultImpl.sol";
import {IConcreteStandardVaultImpl} from "../interface/IConcreteStandardVaultImpl.sol";
import {
    ConcreteCachedVaultStateStorageLib as CachedVaultStateLib
} from "../lib/storage/ConcreteCachedVaultStateStorageLib.sol";

struct ClaimWithdrawalParams {
    uint256 epochID;
    uint256 latestEpochID;
    uint256 epochPrice;
    bool isProcessed;
    uint256 totalAssetsSum;
}

library AsyncVaultHelperLib {
    using Math for uint256;
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────────────────────────────────────
    // Epoch Lifecycle Functions
    // ─────────────────────────────────────────────────────────────────────────────

    function closeEpoch() public {
        ConcreteAsyncVaultImplStorageLib.ConcreteAsyncVaultImplStorage storage $ =
            ConcreteAsyncVaultImplStorageLib.fetch();

        uint256 currentEpoch = $.latestEpochID;

        // Check if previous epoch is processed or if this is the first epoch
        require(
            currentEpoch == 1 || _epochProcessed(currentEpoch - 1),
            IConcreteAsyncVaultImpl.PreviousEpochNotProcessed(currentEpoch - 1)
        );

        // Increment to next epoch (safe to use unchecked as overflow is unrealistic)
        $.latestEpochID = currentEpoch + 1;

        emit IConcreteAsyncVaultImpl.EpochClosed(currentEpoch);
    }

    function processEpoch(uint256 sharePrice, uint256 availableAssets, uint8 decimals) public {
        ConcreteAsyncVaultImplStorageLib.ConcreteAsyncVaultImplStorage storage $ =
            ConcreteAsyncVaultImplStorageLib.fetch();

        uint256 previousEpochID = $.latestEpochID - 1;
        // previous epoch should be not be processed
        require(
            !_epochProcessed(previousEpochID), IConcreteAsyncVaultImpl.PreviousEpochAlreadyProcessed(previousEpochID)
        );
        uint256 requestingShares = $.totalRequestedSharesPerEpoch[previousEpochID];
        uint256 assetsNeeded = 0;
        // add 1 to indicate that the epoch is processed (price cannot be 0)
        $.epochPricePerSharePlusOne[previousEpochID] = sharePrice + 1;

        if (requestingShares == 0) {
            require(availableAssets >= $.pastEpochsUnclaimedAssets, IConcreteStandardVaultImpl.InsufficientBalance());
        } else {
            assetsNeeded = requestingShares.mulDiv(sharePrice, 10 ** decimals, Math.Rounding.Floor);

            require(
                availableAssets >= $.pastEpochsUnclaimedAssets + assetsNeeded,
                IConcreteStandardVaultImpl.InsufficientBalance()
            );
            ERC20_OZ_5_2_0_Lib._burn(address(this), requestingShares);

            // Update accounting
            $.pastEpochsUnclaimedAssets += assetsNeeded;
            CachedVaultStateLib.fetch().cachedTotalAssets -= assetsNeeded;
        }

        emit IConcreteAsyncVaultImpl.EpochProcessed(previousEpochID, requestingShares, assetsNeeded, sharePrice);
    }

    function claimWithdrawal(address asset, address user, uint256[] calldata epochIDs, uint8 decimals) public {
        ConcreteAsyncVaultImplStorageLib.ConcreteAsyncVaultImplStorage storage $ =
            ConcreteAsyncVaultImplStorageLib.fetch();

        ClaimWithdrawalParams memory wwl;
        wwl.latestEpochID = $.latestEpochID;

        uint256 len = epochIDs.length;
        for (uint256 i = 0; i < len; i++) {
            wwl.epochID = epochIDs[i];
            (wwl.epochPrice, wwl.isProcessed) = _epochPriceAndProcessedFlag(wwl.epochID);
            if (!wwl.isProcessed) revert IConcreteAsyncVaultImpl.EpochNotProcessed(wwl.epochID);
            wwl.totalAssetsSum += getUserEpochRequestInAssets(
                user, wwl.epochID, wwl.latestEpochID, wwl.epochPrice, decimals
            );
            $.userEpochRequests[user][wwl.epochID] = 0;
        }

        require(wwl.totalAssetsSum > 0, IConcreteAsyncVaultImpl.NoClaimableRequest());

        // Update accounting
        $.pastEpochsUnclaimedAssets -= wwl.totalAssetsSum;

        // Transfer all assets at once
        IERC20(asset).safeTransfer(user, wwl.totalAssetsSum);

        emit IConcreteAsyncVaultImpl.RequestClaimed(user, wwl.totalAssetsSum, epochIDs);
    }

    function claimUsersBatch(address asset, address[] calldata users, uint256 epochID, uint8 decimals) public {
        ConcreteAsyncVaultImplStorageLib.ConcreteAsyncVaultImplStorage storage $ =
            ConcreteAsyncVaultImplStorageLib.fetch();

        ClaimWithdrawalParams memory wwl;
        wwl.latestEpochID = $.latestEpochID;
        wwl.epochID = epochID;

        (wwl.epochPrice, wwl.isProcessed) = _epochPriceAndProcessedFlag(wwl.epochID);
        if (!wwl.isProcessed) revert IConcreteAsyncVaultImpl.EpochNotProcessed(wwl.epochID);

        wwl.latestEpochID = $.latestEpochID;
        uint256[] memory epochIDs = new uint256[](1);
        epochIDs[0] = epochID;
        address user;
        uint256 assets;

        for (uint256 i = 0; i < users.length; i++) {
            user = users[i];
            assets = getUserEpochRequestInAssets(user, wwl.epochID, wwl.latestEpochID, wwl.epochPrice, decimals);
            if (assets == 0) continue;
            // accounting
            $.userEpochRequests[user][epochID] = 0;
            wwl.totalAssetsSum += assets;
            IERC20(asset).safeTransfer(user, assets);

            emit IConcreteAsyncVaultImpl.RequestClaimed(user, assets, epochIDs);
        }

        require(wwl.totalAssetsSum > 0, IConcreteAsyncVaultImpl.NoClaimableRequest());

        // Update accounting
        $.pastEpochsUnclaimedAssets -= wwl.totalAssetsSum;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Lifecycle Interaction Functions
    // ─────────────────────────────────────────────────────────────────────────────

    function moveRequestToNextEpoch(address user) public {
        ConcreteAsyncVaultImplStorageLib.ConcreteAsyncVaultImplStorage storage $ =
            ConcreteAsyncVaultImplStorageLib.fetch();

        uint256 currentEpoch = $.latestEpochID;
        uint256 nextEpochID = currentEpoch + 1;
        uint256 userBalance = $.userEpochRequests[user][currentEpoch];

        require(userBalance > 0, IConcreteAsyncVaultImpl.NoRequestingShares());

        unchecked {
            $.userEpochRequests[user][currentEpoch] -= userBalance;
            $.userEpochRequests[user][nextEpochID] += userBalance;
            $.totalRequestedSharesPerEpoch[currentEpoch] -= userBalance;
            $.totalRequestedSharesPerEpoch[nextEpochID] += userBalance;
        }
        emit IConcreteAsyncVaultImpl.RequestMovedToNextEpoch(user, userBalance, currentEpoch, nextEpochID);
    }

    function cancelRequest(address user, uint256 epochID) public {
        ConcreteAsyncVaultImplStorageLib.ConcreteAsyncVaultImplStorage storage $ =
            ConcreteAsyncVaultImplStorageLib.fetch();

        require(_epochIsOpen(epochID), IConcreteAsyncVaultImpl.EpochAlreadyClosed(epochID));

        uint256 requestingShares = $.userEpochRequests[user][epochID];
        require(requestingShares > 0, IConcreteAsyncVaultImpl.NoRequestingShares());

        // Clear the request
        $.userEpochRequests[user][epochID] = 0;
        $.totalRequestedSharesPerEpoch[epochID] -= requestingShares;

        // Return shares to user
        ERC20_OZ_5_2_0_Lib._transfer(address(this), user, requestingShares);

        emit IConcreteAsyncVaultImpl.RequestCancelled(user, requestingShares, epochID);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // View Functions
    // ─────────────────────────────────────────────────────────────────────────────

    function getUserEpochRequestInAssets(
        address user,
        uint256 epochID,
        uint256 latestEpochID,
        uint256 epochPrice,
        uint8 decimals
    ) internal view returns (uint256 assets) {
        // Check if epoch is processed (has a price set)
        if (epochPrice == 0 || epochID >= latestEpochID) return 0;

        uint256 shares = ConcreteAsyncVaultImplStorageLib.fetch().userEpochRequests[user][epochID];
        if (shares == 0) return 0;

        assets = shares.mulDiv(epochPrice, 10 ** decimals, Math.Rounding.Floor);
    }

    function getEpochState(uint256 epochID) public view returns (IConcreteAsyncVaultImpl.EpochState) {
        uint256 latestEpochID = ConcreteAsyncVaultImplStorageLib.fetch().latestEpochID;
        if (epochID > latestEpochID) return IConcreteAsyncVaultImpl.EpochState.Inactive;
        if (epochID == latestEpochID) return IConcreteAsyncVaultImpl.EpochState.Active;
        bool isProcessed = _epochProcessed(epochID);
        if (isProcessed) return IConcreteAsyncVaultImpl.EpochState.Processed;
        return IConcreteAsyncVaultImpl.EpochState.Processing;
    }

    function totalRequestedSharesForCurrentEpochs()
        public
        view
        returns (uint256 activeShares, uint256 processingShares, uint256 processedShares)
    {
        ConcreteAsyncVaultImplStorageLib.ConcreteAsyncVaultImplStorage storage $ =
            ConcreteAsyncVaultImplStorageLib.fetch();
        uint256 activeEpochID = $.latestEpochID;
        activeShares = $.totalRequestedSharesPerEpoch[activeEpochID];
        uint256 previousEpochID = activeEpochID - 1;
        uint256 sharesInPreviousEpoch = $.totalRequestedSharesPerEpoch[previousEpochID];
        if (_epochProcessed(previousEpochID)) {
            processedShares = sharesInPreviousEpoch;
        } else {
            processingShares = sharesInPreviousEpoch;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Auxiliary Functions
    // ─────────────────────────────────────────────────────────────────────────────

    function _epochProcessed(uint256 epochID) private view returns (bool isProcessed) {
        (, isProcessed) = _epochPriceAndProcessedFlag(epochID);
    }

    function _epochPriceAndProcessedFlag(uint256 epochID) private view returns (uint256 epochPrice, bool isProcessed) {
        uint256 epochPricePlusOne = ConcreteAsyncVaultImplStorageLib.fetch().epochPricePerSharePlusOne[epochID];
        isProcessed = epochPricePlusOne > 0;
        epochPrice = isProcessed ? epochPricePlusOne - 1 : 0;
    }

    function _epochIsOpen(uint256 epochID) private view returns (bool) {
        return epochID >= ConcreteAsyncVaultImplStorageLib.fetch().latestEpochID;
    }
}
