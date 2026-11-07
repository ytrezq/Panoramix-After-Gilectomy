// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";

/**
 * @title ShareDistributorMock
 * @notice Mock contract that receives LayerZero messages and distributes vault shares to users
 * @dev This contract acts as the destination chain receiver for cross-chain share claims
 * @dev Uses non-upgradeable OApp for testing purposes
 */
contract ShareDistributorMock is OApp {
    // Message type identifiers (must match sender)
    uint16 public constant MSG_TYPE_CLAIM = 1;
    uint16 public constant MSG_TYPE_BATCH_CLAIM = 2;

    // The vault whose shares this distributor manages
    address public targetVault;

    // Events
    event SharesDistributed(address indexed user, uint256 shares, bytes32 guid);
    event BatchSharesDistributed(address[] users, uint256[] shares, bytes32 guid);
    event TargetVaultSet(address indexed vault);

    // Errors
    error InvalidMessageType(uint16 received);
    error InvalidTargetVault();
    error InsufficientShares(uint256 required, uint256 available);

    /**
     * @dev Constructor - initializes the OApp and sets the target vault
     * @param lzEndpoint The LayerZero endpoint for this chain
     * @param _targetVault The vault whose shares will be distributed
     * @param _owner The owner of this contract
     */
    constructor(address lzEndpoint, address _targetVault, address _owner) OApp(lzEndpoint, _owner) Ownable(_owner) {
        if (_targetVault == address(0)) revert InvalidTargetVault();

        targetVault = _targetVault;

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
            // Decode single claim: msgType, user address, shares amount
            (, address user, uint256 shares) = abi.decode(_message, (uint16, address, uint256));

            // Check if distributor has enough shares
            uint256 availableShares = IERC20(targetVault).balanceOf(address(this));
            if (availableShares < shares) {
                revert InsufficientShares(shares, availableShares);
            }

            // Transfer shares from distributor to user
            IERC20(targetVault).transfer(user, shares);

            // Emit event for tracking
            emit SharesDistributed(user, shares, _guid);
        } else if (msgType == MSG_TYPE_BATCH_CLAIM) {
            // Decode batch claim: msgType, addresses array, shares array
            (, address[] memory users, uint256[] memory sharesArray) =
                abi.decode(_message, (uint16, address[], uint256[]));

            // Process each user in the batch
            for (uint256 i = 0; i < users.length; i++) {
                if (sharesArray[i] == 0) continue; // Skip if no shares

                // Check if distributor has enough shares
                uint256 availableShares = IERC20(targetVault).balanceOf(address(this));
                if (availableShares < sharesArray[i]) {
                    revert InsufficientShares(sharesArray[i], availableShares);
                }

                // Transfer shares from distributor to user
                IERC20(targetVault).transfer(users[i], sharesArray[i]);
            }

            // Emit batch event for tracking
            emit BatchSharesDistributed(users, sharesArray, _guid);
        } else {
            revert InvalidMessageType(msgType);
        }
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
     * @param amount Amount of shares to withdraw
     * @param recipient Address to receive the shares
     */
    function emergencyWithdraw(uint256 amount, address recipient) external onlyOwner {
        IERC20(targetVault).transfer(recipient, amount);
    }
}
