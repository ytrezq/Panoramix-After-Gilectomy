// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {
    OAppUpgradeable,
    Origin,
    MessagingFee
} from "@layerzerolabs/oapp-evm-upgradeable/contracts/oapp/OAppUpgradeable.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";

/**
 * @title ShareDistributor
 * @notice Contract that receives LayerZero messages and distributes vault shares to users
 * @dev This contract acts as the destination chain receiver for cross-chain share claims
 * @dev Uses upgradeable pattern with OAppUpgradeable
 */
contract ShareDistributor is OAppUpgradeable {
    // Message type identifiers (must match sender)
    uint16 public constant MSG_TYPE_CLAIM = 1;
    uint16 public constant MSG_TYPE_BATCH_CLAIM = 2;

    // The vault whose shares this distributor manages
    address public targetVault;

    // Mapping to track claimed shares for each user
    // @dev for simplicity not using ERC7201 pattern as this is an auxiliary short-lived contract.
    mapping(address => uint256) public claimedShares;

    // Events
    event SharesDistributed(address indexed user, uint256 shares, bytes32 guid);
    event BatchSharesDistributed(address[] users, uint256[] shares, bytes32 guid);
    event TargetVaultSet(address indexed vault);

    // Errors
    error InvalidMessageType(uint16 received);
    error InvalidTargetVault();
    error InsufficientShares(uint256 required, uint256 available);
    error ArrayLengthMismatch(uint256 usersLength, uint256 sharesLength);

    /**
     * @dev Constructor - disables initializers for the implementation contract
     * @param lzEndpoint The LayerZero endpoint for this chain
     */
    constructor(address lzEndpoint) OAppUpgradeable(lzEndpoint) {
        _disableInitializers();
    }

    /**
     * @notice Initialize the ShareDistributor
     * @param _targetVault The vault whose shares will be distributed
     * @param _owner The owner of this contract
     */
    function initialize(address _targetVault, address _owner) external initializer {
        if (_targetVault == address(0)) revert InvalidTargetVault();

        targetVault = _targetVault;

        __Ownable_init(_owner);
        __OApp_init(_owner);

        emit TargetVaultSet(_targetVault);
    }

    /**
     * @notice Set the target vault (owner only)
     * @param _targetVault The new target vault address
     */
    function setTargetVault(address _targetVault) external onlyOwner {
        if (_targetVault == address(0)) revert InvalidTargetVault();
        targetVault = _targetVault;
        emit TargetVaultSet(_targetVault);
    }

    /**
     * @dev Internal function to handle incoming LayerZero messages
     * @param _guid The unique identifier for the received LayerZero message
     * @param _message The encoded message payload
     */
    function _lzReceive(
        Origin calldata, /*_origin*/
        bytes32 _guid,
        bytes calldata _message,
        address, /*_executor*/
        bytes calldata /*_extraData*/
    )
        internal
        override
    {
        // Decode message type first
        uint16 msgType = abi.decode(_message, (uint16));

        if (msgType == MSG_TYPE_CLAIM) {
            _handleSingleClaim(_message, _guid);
        } else if (msgType == MSG_TYPE_BATCH_CLAIM) {
            _handleBatchClaim(_message, _guid);
        } else {
            revert InvalidMessageType(msgType);
        }
    }

    /**
     * @dev Internal function to handle single user claim
     * @param message The encoded message payload containing msgType, user address, and shares amount
     * @param guid The unique identifier for tracking
     */
    function _handleSingleClaim(bytes calldata message, bytes32 guid) internal {
        // Decode single claim: msgType, user address, shares amount
        (, address user, uint256 shares) = abi.decode(message, (uint16, address, uint256));

        // Check if distributor has enough shares
        uint256 availableShares = IERC20(targetVault).balanceOf(address(this));
        if (availableShares < shares) {
            revert InsufficientShares(shares, availableShares);
        }

        // Record claimed amount before transfer
        claimedShares[user] += shares;

        // Transfer shares from distributor to user
        IERC20(targetVault).transfer(user, shares);

        // Emit event for tracking
        emit SharesDistributed(user, shares, guid);
    }

    /**
     * @dev Internal function to handle batch user claims
     * @param message The encoded message payload containing msgType, addresses array, and shares array
     * @param guid The unique identifier for tracking
     */
    function _handleBatchClaim(bytes calldata message, bytes32 guid) internal {
        // Decode batch claim: msgType, addresses array, shares array
        (, address[] memory users, uint256[] memory sharesArray) = abi.decode(message, (uint16, address[], uint256[]));

        // Validate that both arrays have the same length
        require(users.length == sharesArray.length, ArrayLengthMismatch(users.length, sharesArray.length));

        // Process each user in the batch
        for (uint256 i = 0; i < users.length; i++) {
            if (sharesArray[i] == 0) continue; // Skip if no shares

            // Check if distributor has enough shares
            uint256 availableShares = IERC20(targetVault).balanceOf(address(this));
            if (availableShares < sharesArray[i]) {
                revert InsufficientShares(sharesArray[i], availableShares);
            }

            // Record claimed amount before transfer
            claimedShares[users[i]] += sharesArray[i];

            // Transfer shares from distributor to user
            IERC20(targetVault).transfer(users[i], sharesArray[i]);
        }

        // Emit batch event for tracking
        emit BatchSharesDistributed(users, sharesArray, guid);
    }

    /**
     * @notice View function to check how many shares the distributor has
     * @return The balance of vault shares held by this distributor
     */
    function getAvailableShares() external view returns (uint256) {
        return IERC20(targetVault).balanceOf(address(this));
    }

    /**
     * @notice Emergency function to withdraw shares (owner only)
     * @dev Transfers shares to msg.sender (the owner)
     * @param amount Amount of shares to withdraw
     */
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        IERC20(targetVault).transfer(msg.sender, amount);
    }
}

