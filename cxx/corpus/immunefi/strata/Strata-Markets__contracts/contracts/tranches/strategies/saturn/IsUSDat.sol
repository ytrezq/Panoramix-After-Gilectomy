// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IsUSDat is IERC4626 {

    // ============ Fee State ============

    /// @notice Deposit fee in basis points
    function depositFeeBps () external view returns (uint256);

    /// @notice Address that receives deposit fees
    function feeRecipient () external view returns (address);


    // ============ Vesting State ============

    /// @notice Amount of STRC currently vesting
    function vestingAmount() external view returns (uint256);

    /// @notice Duration of the vesting period in seconds
    function vestingPeriod() external view returns (uint256);

    /// @notice Timestamp of the last reward distribution
    function lastDistributionTimestamp() external view returns (uint256);

    /// @notice Returns the amount of STRC that has not yet vested
    function getUnvestedAmount() external view returns (uint256);

    // ============ Balance Tracking ============

    /// @notice Internally tracked USDat balance (6 decimals)
    function usdatBalance() external view returns (uint256);

    /// @notice Internally tracked STRC balance (6 decimals)
    function strcBalance() external view returns (uint256);

    // ============ Withdrawal Queue ============

    /// @notice Requests a withdrawal of the given shares via the async withdrawal queue
    /// @param shares The amount of sUSDat shares to redeem
    /// @param minUsdatReceived The minimum USDat amount to receive (slippage protection)
    /// @return requestId The ID of the withdrawal request (NFT token ID)
    function requestRedeem(uint256 shares, uint256 minUsdatReceived) external returns (uint256 requestId);

    /// @notice Claims all processed withdrawal requests for the caller
    /// @return totalAmount The total USDat amount claimed
    function claim() external returns (uint256 totalAmount);

    /// @notice Claims specific withdrawal requests by their token IDs
    /// @param tokenIds The NFT token IDs to claim
    /// @return totalAmount The total USDat amount claimed
    function claimBatch(uint256[] calldata tokenIds) external returns (uint256 totalAmount);

    /// @notice Returns the address of the WithdrawalQueueERC721 contract
    function getWithdrawalQueue() external view returns (address);

    // ============ Oracle ============

    /// @notice Returns the address of the STRC price oracle
    function getStrcOracle() external view returns (address);
}

interface ISaturnWithdrawalQueueERC721 {

     /**
     * @notice The lifecycle status of a withdrawal request.
     */
    enum RequestStatus {
        NULL,
        Requested,
        InProgress,
        Processed,
        Claimed
    }
    struct Request {
        uint256 shares;
        uint256 usdatOwed;
        uint256 timestamp;
        uint256 minUsdatReceived;
        RequestStatus status;
    }

    function lockRequests(uint256[] calldata tokenIds) external;

    function processRequests(uint256[] calldata tokenIds,uint256 totalUsdatReceived,uint256 totalStrcSold,uint256 executionPrice) external;

    function requests(uint256 id) external view returns (Request memory);
}
